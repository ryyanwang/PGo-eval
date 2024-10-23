package dqueue

import (
	"fmt"

	"github.com/UBC-NSS/pgo/distsys"
	"github.com/UBC-NSS/pgo/distsys/tla"
)

var _ = new(fmt.Stringer) // unconditionally prevent go compiler from reporting unused fmt import
var _ = distsys.ErrDone
var _ = tla.Value{} // same, for tla

// ONLY ONE PRODUCER (simialar to Producer/Consumer Paradigm in message queue/Kafka)

// AProducer.requester: Stores the ID of the consumer that requested data.
// - read: In AProducer.p2, the producer reads the requester's ID from this resource.
// - write: In AProducer.p1, the producer writes the requester's ID to this resource after receiving a request.

// AProducer.s: Input channel or interface from which the producer reads data to send to consumers.
// - read: In AProducer.p2, the producer reads data from this resource to send to the requester.
// - write: N/A (the producer does not write to 's'; it's an input resource).

// AProducer.net: Networking interface for the producer to communicate with consumers.
// - read: In AProducer.p1, the producer reads requests from consumers via net[self] (net[PRODUCER]).
// - write: In AProducer.p2, the producer writes data to the requester via net[requester].

// MULTIPLE CONSUMERS

// AConsumer.net: Networking interface for the consumer to communicate with the producer.
// - read: In AConsumer.c2, the consumer reads data sent by the producer via net[self].
// - write: In AConsumer.c1, the consumer sends a request to the producer by writing its own ID to net[PRODUCER].

// AConsumer.proc: Output channel or interface where the consumer writes processed data.
// - read: N/A (the consumer does not read from 'proc').
// - write: In AConsumer.c2, the consumer writes the received data to 'proc'.

// iface is Archetype
func NUM_NODES(iface distsys.ArchetypeInterface) tla.Value {
	return tla.ModulePlusSymbol(iface.GetConstant("NUM_CONSUMERS")(), tla.MakeNumber(1))
}

var procTable = distsys.MakeMPCalProcTable()

var jumpTable = distsys.MakeMPCalJumpTable(

	// pendin state, waiting to move to AConsumer.c1
	distsys.MPCalCriticalSection{
		Name: "AConsumer.c",
		Body: func(iface distsys.ArchetypeInterface) error {
			var err error
			_ = err
			if tla.ModuleTRUE.AsBool() {
				return iface.Goto("AConsumer.c1")
			} else {
				return iface.Goto("AConsumer.Done")
			}
			// no statements
		},
	},

	// Requests data to procuer by sending your own identifier
	distsys.MPCalCriticalSection{
		Name: "AConsumer.c1",
		Body: func(iface distsys.ArchetypeInterface) error {

			var err error
			netref, err := iface.RequireArchetypeResourceRef("AConsumer.netremote")
			if err != nil {
				return err
			}
			netResource := iface.Context().GetResourceByHandle(netref).(*CustomRemoteTCPMailboxes)
			netResource.SendMessage(tla.MakeNumber(0))
			return iface.Goto("AConsumer.c2")
		},
	},

	// Proccesses one element read from the network
	distsys.MPCalCriticalSection{
		Name: "AConsumer.c2",
		Body: func(iface distsys.ArchetypeInterface) error {
			var err error
			_ = err

			procRef, nil := iface.RequireArchetypeResourceRef("AConsumer.proc")
			proc := iface.Context().GetResourceByHandle(procRef).(*DummyChannel)

			localRef, nil := iface.RequireArchetypeResourceRef("AConsumer.netlocal")
			localMailbox := iface.Context().GetResourceByHandle(localRef).(*CustomLocalTCPMailboxes)

			value, err := localMailbox.GetMessage()
			if err != nil {
				return distsys.ErrDone
			}
			proc.channel <- value

			return iface.Goto("AConsumer.c")
		},
	},
	distsys.MPCalCriticalSection{
		Name: "AConsumer.Done",
		Body: func(distsys.ArchetypeInterface) error {
			return distsys.ErrDone
		},
	},

	distsys.MPCalCriticalSection{
		Name: "AProducer.p",
		Body: func(iface distsys.ArchetypeInterface) error {
			var err error
			_ = err
			if tla.ModuleTRUE.AsBool() {
				return iface.Goto("AProducer.p1")
			} else {
				return iface.Goto("AProducer.Done")
			}
			// no statements
		},
	},

	// wait for consumer to request data, then send ack
	distsys.MPCalCriticalSection{
		Name: "AProducer.p1",
		Body: func(iface distsys.ArchetypeInterface) error {
			var err error
			_ = err

			netref, err := iface.RequireArchetypeResourceRef("AProducer.netlocal")

			net := iface.Context().GetResourceByHandle(netref).(*CustomLocalTCPMailboxes)

			_, err = net.GetMessage()

			if err != nil {
				return err
			}
			return iface.Goto("AProducer.p2")
		},
	},

	// sends some data to the requestee
	distsys.MPCalCriticalSection{
		Name: "AProducer.p2",
		Body: func(iface distsys.ArchetypeInterface) error {
			var err error
			_ = err

			sRef, err := iface.RequireArchetypeResourceRef("AProducer.s")
			s := iface.Context().GetResourceByHandle(sRef).(*DummyChannel)
			if err != nil {
				return err
			}
			exprRead1, ok := <-s.channel
			if !ok {
				return distsys.ErrDone
			}

			netref, err := iface.RequireArchetypeResourceRef("AProducer.netremote")
			if err != nil {
				return err
			}
			net := iface.Context().GetResourceByHandle(netref).(*CustomRemoteTCPMailboxes)

			net.SendMessage(exprRead1)
			return iface.Goto("AProducer.p")
		},
	},
	distsys.MPCalCriticalSection{
		Name: "AProducer.Done",
		Body: func(distsys.ArchetypeInterface) error {
			return distsys.ErrDone
		},
	},
)

// consumer process
var AConsumer = distsys.MPCalArchetype{
	Name:              "AConsumer",
	Label:             "AConsumer.c",
	RequiredRefParams: []string{"AConsumer.netlocal", "AConsumer.proc", "AConsumer.netremote"},
	RequiredValParams: []string{},
	JumpTable:         jumpTable,
	ProcTable:         procTable,
	PreAmble: func(iface distsys.ArchetypeInterface) {
	},
}

// producer process
var AProducer = distsys.MPCalArchetype{
	Name:              "AProducer",
	Label:             "AProducer.p",
	RequiredRefParams: []string{"AProducer.netlocal", "AProducer.netremote", "AProducer.s"},
	RequiredValParams: []string{},
	JumpTable:         jumpTable,
	ProcTable:         procTable,
	PreAmble: func(iface distsys.ArchetypeInterface) {
		// add list of requester archetype
		iface.EnsureArchetypeResourceLocal("AProducer.requester", tla.Value{})
	},
}
