package dqueue

import (
	"encoding/gob"
	"fmt"
	"io"
	"log"
	"net"
	"testing"
	"time"

	"github.com/UBC-NSS/pgo/distsys/tla"

	"github.com/UBC-NSS/pgo/distsys"
	"github.com/UBC-NSS/pgo/distsys/resources"
)

func TestNUM_NODES(t *testing.T) {
	ctx := distsys.NewMPCalContextWithoutArchetype(
		distsys.DefineConstantValue("NUM_CONSUMERS", tla.MakeNumber(12)))

	result := NUM_NODES(ctx.IFace())
	if result.AsNumber() != 13 {
		t.Errorf("NUM_CONSUMERS(12) should have yielded 13, got %v", result)
	}
}

func TestProducerConsumer(t *testing.T) {
	producerSelf := tla.MakeNumber(0)
	producerInputChannel := make(chan tla.Value, 3)

	consumerSelf := tla.MakeNumber(1)
	consumerOutputChannel := make(chan tla.Value, 3)

	//traceRecorder := trace.MakeLocalFileRecorder("dqueue_trace.txt")
	ctxProducer := distsys.NewMPCalContext(producerSelf, AProducer,
		distsys.DefineConstantValue("PRODUCER", producerSelf),

		// DEFINING PRODUCER NETWORK ARCHETYPE RESOURCE
		distsys.EnsureArchetypeRefParam("net", resources.NewTCPMailboxes(func(index tla.Value) (resources.MailboxKind, string) {
			switch index.AsNumber() {
			case 0:
				return resources.MailboxesLocal, "localhost:8001"
			case 1:
				return resources.MailboxesRemote, "localhost:8002"
			default:
				panic(fmt.Errorf("unknown mailbox index %v", index))
			}
		})),

		// DEFINING PRODUCER INPUT ARCHETYPE RESOURCE
		distsys.EnsureArchetypeRefParam("s", resources.NewInputChan(producerInputChannel)) /*, distsys.SetTraceRecorder(traceRecorder)*/)

	// ctxProducer := distsys.NewMPCalContext(producerSelf, AProducer, distsys.DefineConstantValue("PRODUCER", producerSelf), distsys.EnsureArchetypeRefParam("net", CustomNewTCPMailboxes()))
	// end ctx producer def
	defer ctxProducer.Stop()
	go func() {
		err := ctxProducer.Run()
		if err != nil {
			panic(err)
		}
	}()

	// DEFINING CONSUMER NETOWRK ARCHETYPE RESOURCE
	ctxConsumer := distsys.NewMPCalContext(consumerSelf, AConsumer,
		distsys.DefineConstantValue("PRODUCER", producerSelf),
		distsys.EnsureArchetypeRefParam("net", resources.NewTCPMailboxes(func(index tla.Value) (resources.MailboxKind, string) {
			switch index.AsNumber() {
			case 0:
				return resources.MailboxesRemote, "localhost:8001"
			case 1:
				return resources.MailboxesLocal, "localhost:8002"
			default:
				panic(fmt.Errorf("unknown mailbox index %v", index))
			}
		})),
		distsys.EnsureArchetypeRefParam("proc", resources.NewOutputChan(consumerOutputChannel)) /*, distsys.SetTraceRecorder(traceRecorder)*/)
	// end ctx consumer def
	defer ctxConsumer.Stop()
	go func() {
		err := ctxConsumer.Run()
		if err != nil {
			panic(err)
		}
	}()

	producedValues := []tla.Value{
		tla.MakeNumber(1),
		tla.MakeNumber(2),
		tla.MakeNumber(3),
	}

	// PUTTING VALUES INTO INPUT CHANNEL
	for _, value := range producedValues {
		producerInputChannel <- value
	}

	// MAGIC HAPPENS HERE

	// READING FROM CONSUMER OUTPUT CHANNEL
	consumedValues := []tla.Value{<-consumerOutputChannel, <-consumerOutputChannel, <-consumerOutputChannel}
	close(consumerOutputChannel)
	time.Sleep(100 * time.Millisecond)

	if len(consumedValues) != len(producedValues) {
		t.Fatalf("Consumed values %v did not match produced values %v", consumedValues, producedValues)
	}
	for i := range producedValues {
		if !consumedValues[i].Equal(producedValues[i]) {
			t.Fatalf("Consumed values %v did not match produced values %v", consumedValues, producedValues)
		}
	}
}
func TestProducerConsumerNew(t *testing.T) {
	producerSelf := tla.MakeNumber(0)
	producerInputChannel := make(chan tla.Value, 3)

	// consumerSelf := tla.MakeNumber(1)
	// consumerOutputChannel := make(chan tla.Value, 3)
	//traceRecorder := trace.MakeLocalFileRecorder("dqueue_trace.txt")
	ctxProducer := distsys.NewMPCalContext(producerSelf, AProducer,
		distsys.DefineConstantValue("PRODUCER", producerSelf),
		distsys.EnsureArchetypeRefParam("net", CustomNewLocalTCPMailboxes("localhost:8001")),
		distsys.EnsureArchetypeRefParam("s", resources.NewInputChan(producerInputChannel)))

	// ctxProducer := distsys.NewMPCalContext(producerSelf, AProducer, distsys.DefineConstantValue("PRODUCER", producerSelf), distsys.EnsureArchetypeRefParam("net", CustomNewTCPMailboxes()))
	// end ctx producer def
	defer ctxProducer.Stop()
	go func() {
		err := ctxProducer.Run()
		if err != nil {
			panic(err)
		}
	}()
}

const (
	tcpNetworkBegin = iota
	tcpNetworkValue
	tcpNetworkPreCommit
	tcpNetworkCommit
)

// CustomTCPMailboxes is a custom resource for managing TCP connections without using ReadValue and WriteValue.
type CustomLocalTCPMailboxes struct {
	distsys.ArchetypeResourceLeafMixin

	islocal bool

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
}

func CustomNewLocalTCPMailboxes(listenAddr string) distsys.ArchetypeResource {
	listener, err := net.Listen("tcp", listenAddr)
	if err != nil {
		panic(fmt.Errorf("could not listen on address %s: %w", listenAddr, err))
	}
	res := &CustomLocalTCPMailboxes{
		listener: listener,
	}
	// go listen tcp
	go res.listen()
	return res
}

func (res *CustomLocalTCPMailboxes) connectTo(addr string) (net.Conn, error) {
	conn, err := net.Dial("tcp", addr)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to %s: %w", addr, err)
	}
	return conn, nil
}

func (res *CustomLocalTCPMailboxes) SendMessage(targetID int32, value tla.Value) error {
	// res.lock.RLock()
	conn, exists := res.connections[targetID]
	// res.lock.RUnlock()

	// If no connection exists, create a new one
	if !exists {
		addr, ok := res.addresses[targetID]
		if !ok {
			return fmt.Errorf("unknown target ID: %d", targetID)
		}

		var err error
		conn, err = res.connectTo(addr)
		if err != nil {
			return err
		}

		// Store the connection
		res.lock.Lock()
		res.connections[targetID] = conn
		res.lock.Unlock()
	}

	// Send the message using gob encoder
	encoder := gob.NewEncoder(conn)
	err := encoder.Encode(value)
	if err != nil {
		return fmt.Errorf("failed to send message to %d: %w", targetID, err)
	}

	return nil
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

func (res *CustomLocalTCPMailboxes) handleConn(conn net.Conn) {
	defer func() {
		err := conn.Close()
		if err != nil {
			log.Printf("error closing connection: %v", err)
		}
	}()

	decoder := gob.NewDecoder(conn)
	encoder := gob.NewEncoder(conn)
	var err error

	for {
		// If there was an error in the previous iteration, handle it.
		if err != nil {
			select {
			case <-res.done:
				// If the `res.done` channel is closed, gracefully exit.
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

		// Process the received value.
		// res.lock.RLock()
		if !res.closing {
			// Assuming you want to send an acknowledgment or process the value further.
			err = encoder.Encode(struct{}{}) // This could be replaced with custom processing logic.
			if err == nil {
				res.msgChannel <- recvRecord{
					values: []tla.Value{value},
				}
			}
		}
		// res.lock.RUnlock()
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
