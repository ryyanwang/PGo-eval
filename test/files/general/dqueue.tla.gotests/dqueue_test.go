package dqueue

import (
	"fmt"
	"log"
	"testing"
	"time"

	"github.com/UBC-NSS/pgo/distsys"
	"github.com/UBC-NSS/pgo/distsys/resources"
)

func TestNUM_NODES(t *testing.T) {
	result := NUM_NODES(Constants{NUM_CONSUMERS: distsys.NewTLANumber(12)})
	if result.AsNumber() != 13 {
		t.Errorf("NUM_CONSUMERS(12) should have yielded 13, got %v", result)
	}
}

func TestProducerConsumer(t *testing.T) {
	producerSelf := distsys.NewTLANumber(1)
	producerInputChannel := make(chan distsys.TLAValue, 3)

	consumerSelf := distsys.NewTLANumber(2)
	consumerOutputChannel := make(chan distsys.TLAValue, 3)

	constants := Constants{
		PRODUCER: producerSelf,
	}

	ctxProducer := distsys.NewMPCalContext()
	go func(ctx *distsys.MPCalContext) {
		network := ctx.EnsureArchetypeResourceByName("network", resources.TCPMailboxesArchetypeResourceMaker(func(index distsys.TLAValue) (resources.TCPMailboxKind, string) {
			switch index.AsNumber() {
			case 1:
				return resources.TCPMailboxesLocal, "localhost:8001"
			case 2:
				return resources.TCPMailboxesRemote, "localhost:8002"
			default:
				panic(fmt.Errorf("unknown mailbox index %v", index))
			}
		}))
		s := ctx.EnsureArchetypeResourceByName("s", resources.InputChannelResourceMaker(producerInputChannel))
		err := AProducer(ctx, producerSelf, constants, network, s)
		if err != nil && err != distsys.ErrContextClosed {
			panic(err)
		}
	}(ctxProducer)

	ctxConsumer := distsys.NewMPCalContext()
	go func(ctx *distsys.MPCalContext) {
		network := ctx.EnsureArchetypeResourceByName("network", resources.TCPMailboxesArchetypeResourceMaker(func(index distsys.TLAValue) (resources.TCPMailboxKind, string) {
			switch index.AsNumber() {
			case 1:
				return resources.TCPMailboxesRemote, "localhost:8001"
			case 2:
				return resources.TCPMailboxesLocal, "localhost:8002"
			default:
				panic(fmt.Errorf("unknown mailbox index %v", index))
			}
		}))
		proc := ctx.EnsureArchetypeResourceByName("proc", resources.OutputChannelResourceMaker(consumerOutputChannel))
		err := AConsumer(ctx, consumerSelf, constants, network, proc)
		if err != nil && err != distsys.ErrContextClosed {
			panic(err)
		}
	}(ctxConsumer)

	defer func() {
		if err := ctxProducer.Close(); err != nil {
			log.Println(err)
		}
		if err := ctxConsumer.Close(); err != nil {
			log.Println(err)
		}
	}()

	producedValues := []distsys.TLAValue{
		distsys.NewTLAString("foo"),
		distsys.NewTLAString("bar"),
		distsys.NewTLAString("ping"),
	}
	for _, value := range producedValues {
		producerInputChannel <- value
	}

	consumedValues := []distsys.TLAValue{<-consumerOutputChannel, <-consumerOutputChannel, <-consumerOutputChannel}
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