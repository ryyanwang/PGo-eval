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

			// ask producr for value, block

			var err error
			_ = err
			net, err := iface.RequireArchetypeResourceRef("AConsumer.net")
			if err != nil {
				return err
			}

			// cusnet, err := iface.RequireArchetypeResourceRef("AConsumer.cusnet")

			// cusnet.sendmsg(field1, field,2)

			// consumer sends his own ID to the producer to request something
			err = iface.Write(net, []tla.Value{iface.GetConstant("PRODUCER")()}, iface.Self())
			if err != nil {
				return err
			}

			return iface.Goto("AConsumer.c2")
		},
	},

	// Proccesses one element read from the network
	distsys.MPCalCriticalSection{
		Name: "AConsumer.c2",
		Body: func(iface distsys.ArchetypeInterface) error {
			var err error
			_ = err

			// lock

			// read from consumer

			// write to output (us)
			// go back to beginning of loop
			// unlock

			proc, err := iface.RequireArchetypeResourceRef("AConsumer.proc")
			if err != nil {
				return err
			}

			net0, err := iface.RequireArchetypeResourceRef("AConsumer.net")
			if err != nil {
				return err
			}
			var exprRead tla.Value
			exprRead, err = iface.Read(net0, []tla.Value{iface.Self()})
			if err != nil {
				return err
			}

			//
			err = iface.Write(proc, nil, exprRead)
			if err != nil {
				return err
			}

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

			// get Requester resource
			requester := iface.RequireArchetypeResource("AProducer.requester")

			// get network interface
			net1, err := iface.RequireArchetypeResourceRef("AProducer.net")
			if err != nil {
				return err
			}
			var exprRead0 tla.Value

			// read from own network TCP mailbox to get the
			exprRead0, err = iface.Read(net1, []tla.Value{iface.Self()})
			if err != nil {
				return err
			}

			// send producer ID over network
			// write written value to requestor
			err = iface.Write(requester, nil, exprRead0)
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

			// get network handle
			net2, err := iface.RequireArchetypeResourceRef("AProducer.net")
			if err != nil {
				return err
			}

			// get requestor handle
			requester0 := iface.RequireArchetypeResource("AProducer.requester")

			// get data
			s, err := iface.RequireArchetypeResourceRef("AProducer.s")
			if err != nil {
				return err
			}

			// read data
			var exprRead1 tla.Value
			exprRead1, err = iface.Read(s, nil)
			if err != nil {
				return err
			}

			// read requester value
			var indexRead tla.Value
			indexRead, err = iface.Read(requester0, nil)
			if err != nil {
				return err
			}

			// send data (expr1) over net2 to Requester []tla.value{indexRead}
			err = iface.Write(net2, []tla.Value{indexRead}, exprRead1)
			if err != nil {
				return err
			}
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
	RequiredRefParams: []string{"AConsumer.net", "AConsumer.proc"},
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
	RequiredRefParams: []string{"AProducer.net", "AProducer.s"},
	RequiredValParams: []string{},
	JumpTable:         jumpTable,
	ProcTable:         procTable,
	PreAmble: func(iface distsys.ArchetypeInterface) {
		// add list of requester archetype
		iface.EnsureArchetypeResourceLocal("AProducer.requester", tla.Value{})
	},
}
