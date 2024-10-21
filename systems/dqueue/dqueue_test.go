package dqueue

import (
	"fmt"
	"testing"
	"time"

	"log"

	"github.com/UBC-NSS/pgo/distsys"
	"github.com/UBC-NSS/pgo/distsys/resources"
	"github.com/UBC-NSS/pgo/distsys/tla"
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
	log.Println("Starting TestProducerConsumerNew")

	// Initialize producer
	producerSelf := tla.MakeNumber(0)
	producerInputChannel := make(chan tla.Value, 3)

	// Initialize consumer
	consumerSelf := tla.MakeNumber(1)
	consumerOutputChannel := make(chan tla.Value, 3)

	log.Println("Initializing producer context")
	ctxProducer := distsys.NewMPCalContext(producerSelf, AProducer,
		distsys.DefineConstantValue("PRODUCER", producerSelf),
		distsys.EnsureArchetypeRefParam("netlocal", CustomNewLocalTCPMailboxes("localhost:8001")),
		distsys.EnsureArchetypeRefParam("netremote", CustomNewRemoteTCPMailboxes("localhost:8002")),
		distsys.EnsureArchetypeRefParam("s", NewDummyChannel(producerInputChannel)))

	defer ctxProducer.Stop()
	go func() {
		err := ctxProducer.Run()
		if err != nil {
			log.Fatalf("Producer context run failed: %v", err)
		}
		log.Println("Producer context stopped")
	}()

	log.Println("Initializing consumer context")
	ctxConsumer := distsys.NewMPCalContext(consumerSelf, AConsumer,
		distsys.DefineConstantValue("PRODUCER", producerSelf),
		distsys.EnsureArchetypeRefParam("netlocal", CustomNewLocalTCPMailboxes("localhost:8002")),
		distsys.EnsureArchetypeRefParam("netremote", CustomNewRemoteTCPMailboxes("localhost:8001")),
		distsys.EnsureArchetypeRefParam("proc", NewDummyChannel(consumerOutputChannel)))

	defer ctxConsumer.Stop()
	go func() {
		err := ctxConsumer.Run()
		if err != nil {
			log.Fatalf("Consumer context run failed: %v", err)
		}
		log.Println("Consumer context stopped")
	}()

	// Define produced values
	producedValues := []tla.Value{
		tla.MakeNumber(1),
		tla.MakeNumber(2),
		tla.MakeNumber(3),
	}

	log.Printf("Sending values to producer input channel: %v", producedValues)
	// Send values to the producer's input channel
	for _, value := range producedValues {
		log.Printf("Sending value: %v", value)
		producerInputChannel <- value
	}

	// Retrieve consumed values from the consumer output channel
	log.Println("Receiving values from consumer output channel")
	consumedValues := []tla.Value{<-consumerOutputChannel, <-consumerOutputChannel, <-consumerOutputChannel}
	close(consumerOutputChannel)

	// Allow time for processing
	time.Sleep(100 * time.Millisecond)

	// Compare produced and consumed values
	if len(consumedValues) != len(producedValues) {
		t.Fatalf("Consumed values %v did not match produced values %v", consumedValues, producedValues)
	}
	for i := range producedValues {
		if !consumedValues[i].Equal(producedValues[i]) {
			t.Fatalf("Consumed value %v did not match produced value %v", consumedValues[i], producedValues[i])
		}
	}

	log.Printf("TestProducerConsumerNew completed successfully. Produced: %v, Consumed: %v", producedValues, consumedValues)
	ctxProducer.Stop()
	ctxConsumer.Stop()
}
