package dqueue

import (
	"encoding/gob"
	"fmt"
	"io"
	"log"
	"net"
	"sync"
	"time"

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
	// Self ID
	selfID int32

	closing bool
	// Listener for incoming connections
	listener net.Listener

	// Channel to signal closure
	done chan struct{}

	// Buffer to store received messages (acting like a queue)
	messageBuffer []tla.Value

	// Mutex to protect concurrent access to the message buffer
	bufferMutex sync.Mutex
}

func CustomNewLocalTCPMailboxes(listenAddr string) *CustomLocalTCPMailboxes {
	listener, err := net.Listen("tcp", listenAddr)
	if err != nil {
		panic(fmt.Errorf("could not listen on address %s: %w", listenAddr, err))
	}
	res := &CustomLocalTCPMailboxes{
		listener: listener,
		done:     make(chan struct{}),
		// Initialize the buffer
		messageBuffer: make([]tla.Value, 0),
		// Initialize the maps
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
	for {
		conn, err := res.listener.Accept()
		if err != nil {
			select {
			case <-res.done:
				return
			default:
				panic(fmt.Errorf("error listening on %s: %w", res.listenAddr, err))
			}
		}
		go res.handleConn(conn)
	}
}

// handle incoming connection
func (res *CustomLocalTCPMailboxes) handleConn(conn net.Conn) {
	defer func() {
		err := conn.Close()
		if err != nil {
			log.Printf("error closing connection: %v", err)
		}
	}()

	decoder := gob.NewDecoder(conn)
	var err error

	for {
		// Handle network error or EOF
		if err != nil {
			select {
			case <-res.done:
				return
			default:
				if err != io.EOF {
					log.Printf("network error during handleConn, dropping connection: %s", err)
				}
			}
			return
		}

		var value tla.Value
		errCh := make(chan error)

		// Decode the incoming message in a separate goroutine to handle possible blocking.
		go func() {
			errCh <- decoder.Decode(&value)
		}()

		select {
		case err = <-errCh:
		case <-res.done:
			return
		}

		if err != nil {
			continue
		}

		// Add the received value to the buffer
		res.bufferMutex.Lock()
		res.messageBuffer = append(res.messageBuffer, value)
		res.bufferMutex.Unlock()

		// Further message processing can be added here if needed
	}
}

// GetMessage returns the first item from the buffer (queue)
func (res *CustomLocalTCPMailboxes) GetMessage() (tla.Value, error) {
	for {
		res.bufferMutex.Lock()

		if len(res.messageBuffer) > 0 {
			// Retrieve and remove the first item in the buffer (queue-like behavior)
			message := res.messageBuffer[0]
			res.messageBuffer = res.messageBuffer[1:]

			res.bufferMutex.Unlock()
			return message, nil
		}

		res.bufferMutex.Unlock()

		// Sleep for a short duration before checking again (polling)
		time.Sleep(500 * time.Millisecond)
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
	return tla.Value{}, fmt.Errorf("ReadValue is not supported in CustomTCPMailboxes")
}

func (res *CustomLocalTCPMailboxes) WriteValue(value tla.Value) error {
	return fmt.Errorf("WriteValue is not supported in CustomTCPMailboxes")
}

func (res *CustomLocalTCPMailboxes) Close() error {
	return fmt.Errorf("WriteValue is not supported in CustomTCPMailboxes")
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
	// Initialize the mailbox
	res := &CustomRemoteTCPMailboxes{
		remoteAddress: remoteAddress,
		done:          make(chan struct{}),
	}

	return res
}

// Establishes a connection to the remote address
func (res *CustomRemoteTCPMailboxes) establishConnection() error {
	conn, err := net.Dial("tcp", res.remoteAddress)
	if err != nil {
		return fmt.Errorf("failed to connect to %s: %w", res.remoteAddress, err)
	}

	// Store the connection
	res.connection = conn
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
	err = encoder.Encode(value)
	if err != nil {
		return fmt.Errorf("failed to send message to %s: %w", res.remoteAddress, err)
	}

	return nil
}

// Close closes the active connection and signals completion
func (res *CustomRemoteTCPMailboxes) CloseConn() error {
	close(res.done)
	if res.connection != nil {
		err := res.connection.Close()
		if err != nil {
			return fmt.Errorf("error closing connection: %w", err)
		}
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
	return tla.Value{}, fmt.Errorf("ReadValue is not supported in CustomTCPMailboxes")
}

func (res *CustomRemoteTCPMailboxes) WriteValue(value tla.Value) error {
	return fmt.Errorf("WriteValue is not supported in CustomTCPMailboxes")
}
func (res *CustomRemoteTCPMailboxes) Close() error {
	return fmt.Errorf("WriteValue is not supported in CustomTCPMailboxes")
}

type DummyChannel struct {
	// Reference to a channel of type `chan interface{}`
	channel chan tla.Value
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
	return fmt.Errorf("WriteValue is not supported in CustomTCPMailboxes")
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
