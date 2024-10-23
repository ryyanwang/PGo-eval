package dqueue

import (
	"encoding/gob"
	"fmt"
	"io"
	"log"
	"net"
	"strings"

	"github.com/UBC-NSS/pgo/distsys"
	"github.com/UBC-NSS/pgo/distsys/tla"
	"github.com/UBC-NSS/pgo/distsys/trace"
)

// CustomTCPMailboxes is a custom resource for managing TCP connections without using ReadValue and WriteValue.
type CustomLocalTCPMailboxes struct {
	// ArchetypeResourceLeafMixin

	// Map of addresses for each index
	addresses map[int32]string

	// TCP connections for each index
	connections map[int32]net.Conn

	listenAddr string

	// Listener for incoming connections
	listener net.Listener

	// Channel to signal closure
	done chan struct{}

	// Buffer to store received messages (acting like a queue)
	messageChan chan tla.Value
}

func CustomNewLocalTCPMailboxes(listenAddr string) *CustomLocalTCPMailboxes {
	log.Printf("Starting CustomLocalTCPMailboxes with address: %s", listenAddr)
	listener, err := net.Listen("tcp", listenAddr)
	if err != nil {
		panic(fmt.Errorf("could not listen on address %s: %w", listenAddr, err))
	}
	res := &CustomLocalTCPMailboxes{
		listener:    listener,
		done:        make(chan struct{}),
		messageChan: make(chan tla.Value, 100),
		connections: make(map[int32]net.Conn),
		addresses:   make(map[int32]string),
	}
	// Start listening for incoming connections
	go res.listen()
	return res
}

func (res *CustomLocalTCPMailboxes) Index(tla.Value) (distsys.ArchetypeResource, error) {
	return nil, nil
}

func (res *CustomLocalTCPMailboxes) VClockHint(vclock trace.VClock) trace.VClock {
	return trace.VClock{}
}

func (res *CustomLocalTCPMailboxes) listen() {
	log.Printf("Listening for connections on %s", res.listenAddr)
	for {
		conn, err := res.listener.Accept()
		if err != nil {
			select {
			case <-res.done:
				log.Printf("Listener closed, exiting listen loop")
				return
			default:
				log.Printf("Error accepting connection on %s: %v", res.listenAddr, err)
				continue
			}
		}
		log.Printf("Accepted connection from %s", conn.RemoteAddr())
		go res.handleConn(conn)
	}
}

// handle incoming connection
func (res *CustomLocalTCPMailboxes) handleConn(conn net.Conn) {
	decoder := gob.NewDecoder(conn)
	log.Printf("Started handling connection from %s", conn.RemoteAddr())

	// Start a goroutine to close conn when res.done is closed
	go func() {
		<-res.done
		log.Printf("Received done signal, closing connection for %s", conn.RemoteAddr())
		conn.Close()
	}()

	for {
		var value tla.Value

		select {
		case <-res.done:
			log.Printf("Received done signal, stopping handleConn for %s", conn.RemoteAddr())
			return
		default:
			// Attempt to decode a message without blocking
			err := decoder.Decode(&value)
			if err != nil {
				if err == io.EOF {
					log.Printf("Connection closed by peer: %s", conn.RemoteAddr())
				} else if strings.Contains(err.Error(), "use of closed network connection") {
					log.Printf("Connection closed by us for %s", conn.RemoteAddr())
				} else {
					log.Printf("Error decoding message from %s: %v", conn.RemoteAddr(), err)
				}
				return
			}

			// Log the received message
			log.Printf("Received message from %s: %v", conn.RemoteAddr(), value)

			// Send the received value into the channel, non-blocking
			select {
			case res.messageChan <- value:
				log.Printf("Message sent to messageChan")
			case <-res.done:
				log.Printf("Received done signal, stopping handleConn for %s", conn.RemoteAddr())
				return
			default:
				// Do nothing if unable to send to messageChan immediately
				log.Printf("MessageChan is full, message from %s dropped", conn.RemoteAddr())
			}
		}
	}
}

// GetMessage returns the first item from the buffer (queue)
// GetMessage returns the next message from the channel
func (res *CustomLocalTCPMailboxes) GetMessage() (tla.Value, error) {
	log.Printf("GetMessage called, waiting for message...")
	select {
	case message, ok := <-res.messageChan:
		if !ok {
			return tla.Value{}, fmt.Errorf("message channel closed")
		}
		log.Printf("Message retrieved from channel: %v", message)
		return message, nil
	case <-res.done:
		return tla.Value{}, distsys.ErrDone
	}
}

func (res *CustomLocalTCPMailboxes) Abort() chan struct{} {
	return nil
}

func (res *CustomLocalTCPMailboxes) PreCommit() chan error {
	return nil
}

func (res *CustomLocalTCPMailboxes) Commit() chan struct{} {
	return nil
}

func (res *CustomLocalTCPMailboxes) ReadValue() (tla.Value, error) {
	panic("Panic!?")
}

func (res *CustomLocalTCPMailboxes) WriteValue(value tla.Value) error {
	return fmt.Errorf("WriteValue is not supported in CustomTCPMailboxes")
}

// Close gracefully shuts down the mailbox
func (res *CustomLocalTCPMailboxes) Close() error {
	log.Printf("Closing TCP mailboxes on %s", res.listenAddr)
	// First, close res.done to signal goroutines to exit
	close(res.done)
	// Then, close the listener
	err := res.listener.Close()
	if err != nil {
		log.Printf("Error closing listener: %v", err)
		return err
	}
	// Close the message channel after all goroutines have exited
	close(res.messageChan)
	log.Printf("CustomLocalTCPMailboxes closed")
	return nil
}

type CustomRemoteTCPMailboxes struct {
	distsys.ArchetypeResourceLeafMixin

	// Remote address to connect to
	remoteAddress string

	// TCP connection to the remote server
	connection net.Conn

	// Channel to signal closure
	done chan struct{}
}

// CustomNewRemoteTCPMailboxes initializes the remote TCP mailbox with a single address
func CustomNewRemoteTCPMailboxes(remoteAddress string) *CustomRemoteTCPMailboxes {
	log.Printf("Starting CustomRemoteTCPMailboxes to connect to %s", remoteAddress)
	res := &CustomRemoteTCPMailboxes{
		remoteAddress: remoteAddress,
		done:          make(chan struct{}),
	}
	return res
}

// Establishes a connection to the remote address
func (res *CustomRemoteTCPMailboxes) establishConnection() error {
	log.Printf("Attempting to connect to %s", res.remoteAddress)
	conn, err := net.Dial("tcp", res.remoteAddress)
	if err != nil {
		log.Printf("Failed to connect to %s: %v", res.remoteAddress, err)
		return fmt.Errorf("failed to connect to %s: %w", res.remoteAddress, err)
	}

	// Store the connection
	res.connection = conn
	log.Printf("Connection established to %s", res.remoteAddress)
	return nil
}

// SendMessage sends a message to the remote server
func (res *CustomRemoteTCPMailboxes) SendMessage(value tla.Value) error {
	// If the connection is not established, attempt to connect
	err := res.establishConnection()
	if err != nil {
		return err
	}

	// Send the message using gob encoder
	encoder := gob.NewEncoder(res.connection)
	err = encoder.Encode(&value)
	if err != nil {
		log.Printf("Failed to send message to %s: %v", res.remoteAddress, err)
		return fmt.Errorf("failed to send message to %s: %w", res.remoteAddress, err)
	}

	log.Printf("Message sent to %s: %v", res.remoteAddress, value)
	return nil
}

// Close closes the active connection and signals completion
func (res *CustomRemoteTCPMailboxes) CloseConn() error {
	if res.connection != nil {
		err := res.connection.Close()
		if err != nil {
			log.Printf("Error closing connection to %s: %v", res.remoteAddress, err)
			return fmt.Errorf("error closing connection: %w", err)
		}
		log.Printf("Connection closed to %s", res.remoteAddress)
	}
	return nil
}

func (res *CustomRemoteTCPMailboxes) Abort() chan struct{} {
	return nil
}

func (res *CustomRemoteTCPMailboxes) PreCommit() chan error {
	return nil
}

func (res *CustomRemoteTCPMailboxes) Commit() chan struct{} {
	return nil
}

func (res *CustomRemoteTCPMailboxes) ReadValue() (tla.Value, error) {
	panic("Panic!?")
}

func (res *CustomRemoteTCPMailboxes) WriteValue(value tla.Value) error {
	return fmt.Errorf("WriteValue is not supported in CustomTCPMailboxes")
}
func (res *CustomRemoteTCPMailboxes) Close() error {
	log.Printf("Closing Remote TCP")

	res.CloseConn()
	close(res.done)
	return nil
}

type DummyChannel struct {
	// Reference to a channel of type `chan interface{}`
	channel chan tla.Value
	closed  bool
}

// NewDummyChannel is the constructor that accepts a reference to an existing channel
func NewDummyChannel(ch chan tla.Value) distsys.ArchetypeResource {
	return &DummyChannel{
		channel: ch,
	}
}

// SendMessage sends a message to the channel
// func (d *DummyChannel) SendMessage(value interface{}) {
// 	d.channel <- value
// }

// ReceiveMessage receives a message from the channel
//
//	func (d *DummyChannel) ReceiveMessage() interface{} {
//		return <-d.channel
//	}
func (res *DummyChannel) VClockHint(vclock trace.VClock) trace.VClock {
	return trace.VClock{}
}

func (res *DummyChannel) Abort() chan struct{} {
	return nil
}

func (res *DummyChannel) PreCommit() chan error {
	return nil
}

func (res *DummyChannel) Commit() chan struct{} {
	return nil
}

func (res *DummyChannel) Close() error {

	close(res.channel)
	return nil
}
func (res *DummyChannel) Index(value tla.Value) (distsys.ArchetypeResource, error) {
	return nil, fmt.Errorf("Index method is not supported in DummyChannel")
}
func (res *DummyChannel) ReadValue() (tla.Value, error) {
	return tla.Value{}, fmt.Errorf("ReadValue is not supported in CustomTCPMailboxes")
}

func (res *DummyChannel) WriteValue(value tla.Value) error {
	return fmt.Errorf("WriteValue is not supported in CustomTCPMailboxes")
}
