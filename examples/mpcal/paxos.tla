------------- MODULE paxos --------------------
(*\* Paxos algorithm *)
EXTENDS Integers, Sequences, FiniteSets, TLC

CONSTANTS NUM_PROPOSERS, NUM_ACCEPTORS, NUM_LEARNERS, NUM_SLOTS, MAX_BALLOTS

ASSUME /\ NUM_PROPOSERS \in Nat
       /\ NUM_ACCEPTORS \in Nat
       /\ NUM_LEARNERS \in Nat

AllNodes == 0..(NUM_PROPOSERS+NUM_ACCEPTORS+NUM_LEARNERS-1)

(***************************************************************************
--mpcal Paxos {
  define {
      Proposer == 0..NUM_PROPOSERS-1
      Acceptor == NUM_PROPOSERS..(NUM_PROPOSERS+NUM_ACCEPTORS-1)
      Learner == (NUM_PROPOSERS+NUM_ACCEPTORS)..(NUM_PROPOSERS+NUM_ACCEPTORS+NUM_LEARNERS-1)
      Slots == 1..NUM_SLOTS
      Ballots == 0..MAX_BALLOTS
      PREPARE_MSG == 0
      PROMISE_MSG == 1
      PROPOSE_MSG == 2
      ACCEPT_MSG == 3
      CHOSEN_MSG == 4
  }

  macro Broadcast(mailboxes, msg, i, stop)
  {
      while (i <= stop) {
          mailboxes[i] := msg;
          i := i + 1;
      };
  }

  mapping macro FIFOChannel {
      read {
          await Len($variable) > 0;
          with (msg = Head($variable)) {
              $variable := Tail($variable);
              yield msg;
          };
      }

      write {
          yield Append($variable, $value);
      }
  }

  mapping macro Log {
      read {
          assert(FALSE);
      }

      write {
          yield $variable \union {$value};
      }
  }

  \* Acceptor process actions
  archetype ALearner(ref mailboxes, ref decided)
  variables accepts = <<>>,
            cnt = 0,
            j,
            entry,
            msg;
  {
L:  while (TRUE) {
        msg := mailboxes[self];
L1:     if (msg.type = ACCEPT_MSG) {
            accepts := Append(accepts, msg);
            j := 1;
            cnt := 0;
L2:         while (j <= Len(accepts)) {
                entry := accepts[j];
                if (entry.slot = msg.slot /\ entry.bal = msg.bal /\ entry.val = msg.val) {
                    cnt := cnt + 1;
                };
                j := j + 1;
            };
            if (cnt*2 > Cardinality(Acceptor)) {
                decided[msg.slot] := msg.val;
            };
        };
    };
  }

  \* Acceptor process actions
  archetype AAcceptor(ref mailboxes)
  variables maxBal = -1,
            aidx,
            hVal = <<>>,
            msg;
  {
A:  while (TRUE) {
        msg := mailboxes[self];
A1:     if (msg.type = PREPARE_MSG /\ msg.bal > maxBal) {
A2:         maxBal := msg.bal;
            mailboxes[msg.sender] := [type |-> PROMISE_MSG, sender |-> self, bal |-> maxBal, slot |-> msg.slot, val |-> msg.val, hv |-> hVal];
        } elseif (msg.type = PROPOSE_MSG /\ msg.bal >= maxBal) {
A3:         maxBal := msg.bal;
            aidx := NUM_PROPOSERS+NUM_ACCEPTORS;
            hVal := Append(hVal, [slot |-> msg.slot, bal |-> msg.bal, val |-> msg.val]);
            mailboxes[msg.sender] := [type |-> ACCEPT_MSG, sender |-> self, bal |-> maxBal, slot |-> msg.slot, val |-> msg.val, hv |-> hVal];
loop2:      Broadcast(mailboxes, [type |-> ACCEPT_MSG, sender |-> self, bal |-> maxBal, slot |-> msg.slot, val |-> msg.val, hv |-> hVal], aidx, NUM_PROPOSERS+NUM_ACCEPTORS+NUM_LEARNERS-1);
        } elseif (msg.type = PROPOSE_MSG /\ msg.bal < maxBal) {
A4:         mailboxes[msg.sender] := [type |-> ACCEPT_MSG, sender |-> self, bal |-> maxBal, slot |-> msg.slot, val |-> msg.val, hv |-> hVal];
        }
    }
  }

  \* Leader process
  archetype AProposer(ref mailboxes)
  variables b,
            s = 1,
            elected = FALSE,
            pVal = <<>>,
            max = [slot |-> -1, bal |-> -1, val |-> -1],
            j,
            entry,
            promises,
            accepts = 0,
            v,
            resp,
            idx = NUM_PROPOSERS;
  {
Pre:b := self;
P:  while (s \in Slots /\ b \in Ballots) {
P1:     if (elected) {
            accepts := 0;
            v := self;
            j := 1;
P5:         while (j <= Len(pVal)) {
                entry := Head(pVal[j]);
                if (entry.slot = s /\ entry.bal >= max.bal) {
                    v := entry.val;
                    max := entry;
                };
                j := j + 1;
            };

loop1:      Broadcast(mailboxes, [type |-> PROPOSE_MSG, bal |-> b, sender |-> self, slot |-> s, val |-> v], idx, NUM_PROPOSERS+NUM_ACCEPTORS-1);
            idx := NUM_PROPOSERS;
            \* await responses, abort if necessary
search1:    while (accepts*2 < Cardinality(Acceptor) /\ elected) {
                \* Wait for accept message
                resp := mailboxes[self];
                if (resp.type = ACCEPT_MSG) {
                    \* Is it still from a current term?
P6:                 if (resp.bal > b \/ resp.slot # s \/ resp.val # v) {
                        \* Pre-empted by another proposer
                        elected := FALSE;
                    } else {
                        accepts := accepts + 1;
                    };
                };
            };
            \* If still elected, then we must have a majority of accepts
P7:         if (elected) {
P8:             s := s + 1;
            };
        } else {
loop3:      Broadcast(mailboxes, [type |-> PREPARE_MSG, bal |-> b, sender |-> self, slot |-> s, val |-> v], idx, NUM_PROPOSERS+NUM_ACCEPTORS-1);
            idx := NUM_PROPOSERS;
            promises := 0;
            \* Wait for response from majority of acceptors
search2:    while (~elected) {
                \* Wait for promise
                resp := mailboxes[self];
                if (resp.type = PROMISE_MSG) {
                    pVal := pVal \o resp.hv;
    
                    \* Is it still from a current term?
P2:                 if (resp.bal > b) {
                        \* Pre-empted, try again for election
                        b := b+NUM_PROPOSERS;
loop4:                  Broadcast(mailboxes, [type |-> PREPARE_MSG, bal |-> b, sender |-> self, slot |-> s, val |-> v], idx, NUM_PROPOSERS+NUM_ACCEPTORS-1);
                        idx := NUM_PROPOSERS;
                    } else {
P3:                     if (resp.bal = b) {
                            promises := promises + 1;
P4:                         if (promises*2 > Cardinality(Acceptor)) {
                                elected := TRUE;
                            };
                        };
                    };
                };
            };
        };
   }
  }
    variables
        network = [id \in AllNodes |-> <<>>];

    fair process (proposer \in Proposer) == instance AProposer(ref network)
        mapping network[_] via FIFOChannel;

    fair process (acceptor \in Acceptor) == instance AAcceptor(ref network)
        mapping network[_] via FIFOChannel;

    fair process (learner \in Learner) == instance ALearner(ref network, [x \in Slots |-> {}])
        mapping @2[_] via Log
        mapping network[_] via FIFOChannel;
}

\* BEGIN PLUSCAL TRANSLATION
--algorithm Paxos {
    variables network = [id \in AllNodes |-> <<>>], mailboxesWrite, mailboxesWrite0, mailboxesRead, mailboxesWrite1, mailboxesWrite2, mailboxesWrite3, mailboxesWrite4, mailboxesWrite5, mailboxesWrite6, mailboxesWrite7, mailboxesRead0, mailboxesWrite8, mailboxesWrite9, mailboxesWrite10, mailboxesWrite11, mailboxesWrite12, mailboxesWrite13, mailboxesRead1, mailboxesWrite14, decidedWrite, decidedWrite0, decidedWrite1, decidedWrite2, decidedWrite3;
    define {
        Proposer == (0) .. ((NUM_PROPOSERS) - (1))
        Acceptor == (NUM_PROPOSERS) .. ((NUM_PROPOSERS) + ((NUM_ACCEPTORS) - (1)))
        Learner == ((NUM_PROPOSERS) + (NUM_ACCEPTORS)) .. (((NUM_PROPOSERS) + (NUM_ACCEPTORS)) + ((NUM_LEARNERS) - (1)))
        Slots == (1) .. (NUM_SLOTS)
        Ballots == (0) .. (MAX_BALLOTS)
        PREPARE_MSG == 0
        PROMISE_MSG == 1
        PROPOSE_MSG == 2
        ACCEPT_MSG == 3
        CHOSEN_MSG == 4
    }
    fair process (proposer \in Proposer)
    variables b, s = 1, elected = FALSE, pVal = <<>>, max = [slot |-> -(1), bal |-> -(1), val |-> -(1)], j, entry, promises, accepts = 0, v, resp, idx = NUM_PROPOSERS;
    {
        Pre:
            b := self;
        P:
            if (((s) \in (Slots)) /\ ((b) \in (Ballots))) {
                P1:
                    if (elected) {
                        accepts := 0;
                        v := self;
                        j := 1;
                        P5:
                            if ((j) <= (Len(pVal))) {
                                entry := Head(pVal[j]);
                                if ((((entry).slot) = (s)) /\ (((entry).bal) >= ((max).bal))) {
                                    v := (entry).val;
                                    max := entry;
                                };
                                j := (j) + (1);
                                goto P5;
                            };
                        
                        loop1:
                            if ((idx) <= ((NUM_PROPOSERS) + ((NUM_ACCEPTORS) - (1)))) {
                                mailboxesWrite := [network EXCEPT ![idx] = Append(network[idx], [type |-> PROPOSE_MSG, bal |-> b, sender |-> self, slot |-> s, val |-> v])];
                                idx := (idx) + (1);
                                mailboxesWrite0 := mailboxesWrite;
                                network := mailboxesWrite0;
                                goto loop1;
                            } else {
                                idx := NUM_PROPOSERS;
                                mailboxesWrite0 := network;
                                network := mailboxesWrite0;
                            };
                        
                        search1:
                            if ((((accepts) * (2)) < (Cardinality(Acceptor))) /\ (elected)) {
                                await (Len(network[self])) > (0);
                                with (msg0 = Head(network[self])) {
                                    mailboxesWrite := [network EXCEPT ![self] = Tail(network[self])];
                                    mailboxesRead := msg0;
                                };
                                resp := mailboxesRead;
                                if (((resp).type) = (ACCEPT_MSG)) {
                                    network := mailboxesWrite;
                                    P6:
                                        if (((((resp).bal) > (b)) \/ (((resp).slot) # (s))) \/ (((resp).val) # (v))) {
                                            elected := FALSE;
                                            goto search1;
                                        } else {
                                            accepts := (accepts) + (1);
                                            goto search1;
                                        };
                                
                                } else {
                                    goto search1;
                                };
                            };
                        
                        P7:
                            if (elected) {
                                P8:
                                    s := (s) + (1);
                                    goto P;
                            
                            } else {
                                goto P;
                            };
                    
                    } else {
                        loop3:
                            if ((idx) <= ((NUM_PROPOSERS) + ((NUM_ACCEPTORS) - (1)))) {
                                mailboxesWrite := [network EXCEPT ![idx] = Append(network[idx], [type |-> PREPARE_MSG, bal |-> b, sender |-> self, slot |-> s, val |-> v])];
                                idx := (idx) + (1);
                                mailboxesWrite1 := mailboxesWrite;
                                network := mailboxesWrite1;
                                goto loop3;
                            } else {
                                idx := NUM_PROPOSERS;
                                promises := 0;
                                mailboxesWrite1 := network;
                                network := mailboxesWrite1;
                            };
                        
                        search2:
                            if (~(elected)) {
                                await (Len(network[self])) > (0);
                                with (msg1 = Head(network[self])) {
                                    mailboxesWrite := [network EXCEPT ![self] = Tail(network[self])];
                                    mailboxesRead := msg1;
                                };
                                resp := mailboxesRead;
                                if (((resp).type) = (PROMISE_MSG)) {
                                    pVal := (pVal) \o ((resp).hv);
                                    network := mailboxesWrite;
                                    P2:
                                        if (((resp).bal) > (b)) {
                                            b := (b) + (NUM_PROPOSERS);
                                            loop4:
                                                if ((idx) <= ((NUM_PROPOSERS) + ((NUM_ACCEPTORS) - (1)))) {
                                                    mailboxesWrite := [network EXCEPT ![idx] = Append(network[idx], [type |-> PREPARE_MSG, bal |-> b, sender |-> self, slot |-> s, val |-> v])];
                                                    idx := (idx) + (1);
                                                    mailboxesWrite2 := mailboxesWrite;
                                                    network := mailboxesWrite2;
                                                    goto loop4;
                                                } else {
                                                    idx := NUM_PROPOSERS;
                                                    mailboxesWrite2 := network;
                                                    network := mailboxesWrite2;
                                                    goto search2;
                                                };
                                        
                                        } else {
                                            P3:
                                                if (((resp).bal) = (b)) {
                                                    promises := (promises) + (1);
                                                    P4:
                                                        if (((promises) * (2)) > (Cardinality(Acceptor))) {
                                                            elected := TRUE;
                                                            goto search2;
                                                        } else {
                                                            goto search2;
                                                        };
                                                
                                                } else {
                                                    goto search2;
                                                };
                                        
                                        };
                                
                                } else {
                                    mailboxesWrite4 := network;
                                    mailboxesWrite5 := mailboxesWrite4;
                                    network := mailboxesWrite5;
                                    goto search2;
                                };
                            } else {
                                mailboxesWrite5 := network;
                                network := mailboxesWrite5;
                                goto P;
                            };
                    
                    };
            
            } else {
                mailboxesWrite7 := network;
                network := mailboxesWrite7;
            };
    
    }
    fair process (acceptor \in Acceptor)
    variables maxBal = -(1), aidx, hVal = <<>>, msg;
    {
        A:
            if (TRUE) {
                await (Len(network[self])) > (0);
                with (msg2 = Head(network[self])) {
                    mailboxesWrite8 := [network EXCEPT ![self] = Tail(network[self])];
                    mailboxesRead0 := msg2;
                };
                msg := mailboxesRead0;
                network := mailboxesWrite8;
                A1:
                    if ((((msg).type) = (PREPARE_MSG)) /\ (((msg).bal) > (maxBal))) {
                        A2:
                            maxBal := (msg).bal;
                            mailboxesWrite8 := [network EXCEPT ![(msg).sender] = Append(network[(msg).sender], [type |-> PROMISE_MSG, sender |-> self, bal |-> maxBal, slot |-> (msg).slot, val |-> (msg).val, hv |-> hVal])];
                            network := mailboxesWrite8;
                            goto A;
                    
                    } else {
                        if ((((msg).type) = (PROPOSE_MSG)) /\ (((msg).bal) >= (maxBal))) {
                            A3:
                                maxBal := (msg).bal;
                                aidx := (NUM_PROPOSERS) + (NUM_ACCEPTORS);
                                hVal := Append(hVal, [slot |-> (msg).slot, bal |-> (msg).bal, val |-> (msg).val]);
                                mailboxesWrite8 := [network EXCEPT ![(msg).sender] = Append(network[(msg).sender], [type |-> ACCEPT_MSG, sender |-> self, bal |-> maxBal, slot |-> (msg).slot, val |-> (msg).val, hv |-> hVal])];
                                network := mailboxesWrite8;
                            
                            loop2:
                                if ((aidx) <= (((NUM_PROPOSERS) + (NUM_ACCEPTORS)) + ((NUM_LEARNERS) - (1)))) {
                                    mailboxesWrite8 := [network EXCEPT ![aidx] = Append(network[aidx], [type |-> ACCEPT_MSG, sender |-> self, bal |-> maxBal, slot |-> (msg).slot, val |-> (msg).val, hv |-> hVal])];
                                    aidx := (aidx) + (1);
                                    mailboxesWrite9 := mailboxesWrite8;
                                    network := mailboxesWrite9;
                                    goto loop2;
                                } else {
                                    mailboxesWrite9 := network;
                                    network := mailboxesWrite9;
                                    goto A;
                                };
                        
                        } else {
                            if ((((msg).type) = (PROPOSE_MSG)) /\ (((msg).bal) < (maxBal))) {
                                A4:
                                    mailboxesWrite8 := [network EXCEPT ![(msg).sender] = Append(network[(msg).sender], [type |-> ACCEPT_MSG, sender |-> self, bal |-> maxBal, slot |-> (msg).slot, val |-> (msg).val, hv |-> hVal])];
                                    network := mailboxesWrite8;
                                    goto A;
                            
                            } else {
                                mailboxesWrite10 := network;
                                mailboxesWrite11 := mailboxesWrite10;
                                mailboxesWrite12 := mailboxesWrite11;
                                network := mailboxesWrite12;
                                goto A;
                            };
                        };
                    };
            
            } else {
                mailboxesWrite13 := network;
                network := mailboxesWrite13;
            };
    
    }
    fair process (learner \in Learner)
    variables decidedLocal = [x \in Slots |-> {}], accepts = <<>>, cnt = 0, j, entry, msg;
    {
        L:
            if (TRUE) {
                await (Len(network[self])) > (0);
                with (msg3 = Head(network[self])) {
                    mailboxesWrite14 := [network EXCEPT ![self] = Tail(network[self])];
                    mailboxesRead1 := msg3;
                };
                msg := mailboxesRead1;
                network := mailboxesWrite14;
                L1:
                    if (((msg).type) = (ACCEPT_MSG)) {
                        accepts := Append(accepts, msg);
                        j := 1;
                        cnt := 0;
                        L2:
                            if ((j) <= (Len(accepts))) {
                                entry := accepts[j];
                                if (((((entry).slot) = ((msg).slot)) /\ (((entry).bal) = ((msg).bal))) /\ (((entry).val) = ((msg).val))) {
                                    cnt := (cnt) + (1);
                                };
                                j := (j) + (1);
                                decidedWrite1 := decidedLocal;
                                decidedLocal := decidedWrite1;
                                goto L2;
                            } else {
                                if (((cnt) * (2)) > (Cardinality(Acceptor))) {
                                    decidedWrite := [decidedLocal EXCEPT ![(msg).slot] = (decidedLocal[(msg).slot]) \union ({(msg).val})];
                                    decidedWrite0 := decidedWrite;
                                    decidedWrite1 := decidedWrite0;
                                    decidedLocal := decidedWrite1;
                                    goto L;
                                } else {
                                    decidedWrite0 := decidedLocal;
                                    decidedWrite1 := decidedWrite0;
                                    decidedLocal := decidedWrite1;
                                    goto L;
                                };
                            };
                    
                    } else {
                        decidedWrite2 := decidedLocal;
                        decidedLocal := decidedWrite2;
                        goto L;
                    };
            
            } else {
                decidedWrite3 := decidedLocal;
                decidedLocal := decidedWrite3;
            };
    
    }
}
\* END PLUSCAL TRANSLATION


***************************************************************************)

\* BEGIN TRANSLATION
\* Process variable j of process proposer at line 222 col 106 changed to j_
\* Process variable entry of process proposer at line 222 col 109 changed to entry_
\* Process variable accepts of process proposer at line 222 col 126 changed to accepts_
\* Process variable msg of process acceptor at line 373 col 49 changed to msg_
CONSTANT defaultInitValue
VARIABLES network, mailboxesWrite, mailboxesWrite0, mailboxesRead, 
          mailboxesWrite1, mailboxesWrite2, mailboxesWrite3, mailboxesWrite4, 
          mailboxesWrite5, mailboxesWrite6, mailboxesWrite7, mailboxesRead0, 
          mailboxesWrite8, mailboxesWrite9, mailboxesWrite10, 
          mailboxesWrite11, mailboxesWrite12, mailboxesWrite13, 
          mailboxesRead1, mailboxesWrite14, decidedWrite, decidedWrite0, 
          decidedWrite1, decidedWrite2, decidedWrite3, pc

(* define statement *)
Proposer == (0) .. ((NUM_PROPOSERS) - (1))
Acceptor == (NUM_PROPOSERS) .. ((NUM_PROPOSERS) + ((NUM_ACCEPTORS) - (1)))
Learner == ((NUM_PROPOSERS) + (NUM_ACCEPTORS)) .. (((NUM_PROPOSERS) + (NUM_ACCEPTORS)) + ((NUM_LEARNERS) - (1)))
Slots == (1) .. (NUM_SLOTS)
Ballots == (0) .. (MAX_BALLOTS)
PREPARE_MSG == 0
PROMISE_MSG == 1
PROPOSE_MSG == 2
ACCEPT_MSG == 3
CHOSEN_MSG == 4

VARIABLES b, s, elected, pVal, max, j_, entry_, promises, accepts_, v, resp, 
          idx, maxBal, aidx, hVal, msg_, decidedLocal, accepts, cnt, j, entry, 
          msg

vars == << network, mailboxesWrite, mailboxesWrite0, mailboxesRead, 
           mailboxesWrite1, mailboxesWrite2, mailboxesWrite3, mailboxesWrite4, 
           mailboxesWrite5, mailboxesWrite6, mailboxesWrite7, mailboxesRead0, 
           mailboxesWrite8, mailboxesWrite9, mailboxesWrite10, 
           mailboxesWrite11, mailboxesWrite12, mailboxesWrite13, 
           mailboxesRead1, mailboxesWrite14, decidedWrite, decidedWrite0, 
           decidedWrite1, decidedWrite2, decidedWrite3, pc, b, s, elected, 
           pVal, max, j_, entry_, promises, accepts_, v, resp, idx, maxBal, 
           aidx, hVal, msg_, decidedLocal, accepts, cnt, j, entry, msg >>

ProcSet == (Proposer) \cup (Acceptor) \cup (Learner)

Init == (* Global variables *)
        /\ network = [id \in AllNodes |-> <<>>]
        /\ mailboxesWrite = defaultInitValue
        /\ mailboxesWrite0 = defaultInitValue
        /\ mailboxesRead = defaultInitValue
        /\ mailboxesWrite1 = defaultInitValue
        /\ mailboxesWrite2 = defaultInitValue
        /\ mailboxesWrite3 = defaultInitValue
        /\ mailboxesWrite4 = defaultInitValue
        /\ mailboxesWrite5 = defaultInitValue
        /\ mailboxesWrite6 = defaultInitValue
        /\ mailboxesWrite7 = defaultInitValue
        /\ mailboxesRead0 = defaultInitValue
        /\ mailboxesWrite8 = defaultInitValue
        /\ mailboxesWrite9 = defaultInitValue
        /\ mailboxesWrite10 = defaultInitValue
        /\ mailboxesWrite11 = defaultInitValue
        /\ mailboxesWrite12 = defaultInitValue
        /\ mailboxesWrite13 = defaultInitValue
        /\ mailboxesRead1 = defaultInitValue
        /\ mailboxesWrite14 = defaultInitValue
        /\ decidedWrite = defaultInitValue
        /\ decidedWrite0 = defaultInitValue
        /\ decidedWrite1 = defaultInitValue
        /\ decidedWrite2 = defaultInitValue
        /\ decidedWrite3 = defaultInitValue
        (* Process proposer *)
        /\ b = [self \in Proposer |-> defaultInitValue]
        /\ s = [self \in Proposer |-> 1]
        /\ elected = [self \in Proposer |-> FALSE]
        /\ pVal = [self \in Proposer |-> <<>>]
        /\ max = [self \in Proposer |-> [slot |-> -(1), bal |-> -(1), val |-> -(1)]]
        /\ j_ = [self \in Proposer |-> defaultInitValue]
        /\ entry_ = [self \in Proposer |-> defaultInitValue]
        /\ promises = [self \in Proposer |-> defaultInitValue]
        /\ accepts_ = [self \in Proposer |-> 0]
        /\ v = [self \in Proposer |-> defaultInitValue]
        /\ resp = [self \in Proposer |-> defaultInitValue]
        /\ idx = [self \in Proposer |-> NUM_PROPOSERS]
        (* Process acceptor *)
        /\ maxBal = [self \in Acceptor |-> -(1)]
        /\ aidx = [self \in Acceptor |-> defaultInitValue]
        /\ hVal = [self \in Acceptor |-> <<>>]
        /\ msg_ = [self \in Acceptor |-> defaultInitValue]
        (* Process learner *)
        /\ decidedLocal = [self \in Learner |-> [x \in Slots |-> {}]]
        /\ accepts = [self \in Learner |-> <<>>]
        /\ cnt = [self \in Learner |-> 0]
        /\ j = [self \in Learner |-> defaultInitValue]
        /\ entry = [self \in Learner |-> defaultInitValue]
        /\ msg = [self \in Learner |-> defaultInitValue]
        /\ pc = [self \in ProcSet |-> CASE self \in Proposer -> "Pre"
                                        [] self \in Acceptor -> "A"
                                        [] self \in Learner -> "L"]

Pre(self) == /\ pc[self] = "Pre"
             /\ b' = [b EXCEPT ![self] = self]
             /\ pc' = [pc EXCEPT ![self] = "P"]
             /\ UNCHANGED << network, mailboxesWrite, mailboxesWrite0, 
                             mailboxesRead, mailboxesWrite1, mailboxesWrite2, 
                             mailboxesWrite3, mailboxesWrite4, mailboxesWrite5, 
                             mailboxesWrite6, mailboxesWrite7, mailboxesRead0, 
                             mailboxesWrite8, mailboxesWrite9, 
                             mailboxesWrite10, mailboxesWrite11, 
                             mailboxesWrite12, mailboxesWrite13, 
                             mailboxesRead1, mailboxesWrite14, decidedWrite, 
                             decidedWrite0, decidedWrite1, decidedWrite2, 
                             decidedWrite3, s, elected, pVal, max, j_, entry_, 
                             promises, accepts_, v, resp, idx, maxBal, aidx, 
                             hVal, msg_, decidedLocal, accepts, cnt, j, entry, 
                             msg >>

P(self) == /\ pc[self] = "P"
           /\ IF ((s[self]) \in (Slots)) /\ ((b[self]) \in (Ballots))
                 THEN /\ pc' = [pc EXCEPT ![self] = "P1"]
                      /\ UNCHANGED << network, mailboxesWrite7 >>
                 ELSE /\ mailboxesWrite7' = network
                      /\ network' = mailboxesWrite7'
                      /\ pc' = [pc EXCEPT ![self] = "Done"]
           /\ UNCHANGED << mailboxesWrite, mailboxesWrite0, mailboxesRead, 
                           mailboxesWrite1, mailboxesWrite2, mailboxesWrite3, 
                           mailboxesWrite4, mailboxesWrite5, mailboxesWrite6, 
                           mailboxesRead0, mailboxesWrite8, mailboxesWrite9, 
                           mailboxesWrite10, mailboxesWrite11, 
                           mailboxesWrite12, mailboxesWrite13, mailboxesRead1, 
                           mailboxesWrite14, decidedWrite, decidedWrite0, 
                           decidedWrite1, decidedWrite2, decidedWrite3, b, s, 
                           elected, pVal, max, j_, entry_, promises, accepts_, 
                           v, resp, idx, maxBal, aidx, hVal, msg_, 
                           decidedLocal, accepts, cnt, j, entry, msg >>

P1(self) == /\ pc[self] = "P1"
            /\ IF elected[self]
                  THEN /\ accepts_' = [accepts_ EXCEPT ![self] = 0]
                       /\ v' = [v EXCEPT ![self] = self]
                       /\ j_' = [j_ EXCEPT ![self] = 1]
                       /\ pc' = [pc EXCEPT ![self] = "P5"]
                  ELSE /\ pc' = [pc EXCEPT ![self] = "loop3"]
                       /\ UNCHANGED << j_, accepts_, v >>
            /\ UNCHANGED << network, mailboxesWrite, mailboxesWrite0, 
                            mailboxesRead, mailboxesWrite1, mailboxesWrite2, 
                            mailboxesWrite3, mailboxesWrite4, mailboxesWrite5, 
                            mailboxesWrite6, mailboxesWrite7, mailboxesRead0, 
                            mailboxesWrite8, mailboxesWrite9, mailboxesWrite10, 
                            mailboxesWrite11, mailboxesWrite12, 
                            mailboxesWrite13, mailboxesRead1, mailboxesWrite14, 
                            decidedWrite, decidedWrite0, decidedWrite1, 
                            decidedWrite2, decidedWrite3, b, s, elected, pVal, 
                            max, entry_, promises, resp, idx, maxBal, aidx, 
                            hVal, msg_, decidedLocal, accepts, cnt, j, entry, 
                            msg >>

P5(self) == /\ pc[self] = "P5"
            /\ IF (j_[self]) <= (Len(pVal[self]))
                  THEN /\ entry_' = [entry_ EXCEPT ![self] = Head(pVal[self][j_[self]])]
                       /\ IF (((entry_'[self]).slot) = (s[self])) /\ (((entry_'[self]).bal) >= ((max[self]).bal))
                             THEN /\ v' = [v EXCEPT ![self] = (entry_'[self]).val]
                                  /\ max' = [max EXCEPT ![self] = entry_'[self]]
                             ELSE /\ TRUE
                                  /\ UNCHANGED << max, v >>
                       /\ j_' = [j_ EXCEPT ![self] = (j_[self]) + (1)]
                       /\ pc' = [pc EXCEPT ![self] = "P5"]
                  ELSE /\ pc' = [pc EXCEPT ![self] = "loop1"]
                       /\ UNCHANGED << max, j_, entry_, v >>
            /\ UNCHANGED << network, mailboxesWrite, mailboxesWrite0, 
                            mailboxesRead, mailboxesWrite1, mailboxesWrite2, 
                            mailboxesWrite3, mailboxesWrite4, mailboxesWrite5, 
                            mailboxesWrite6, mailboxesWrite7, mailboxesRead0, 
                            mailboxesWrite8, mailboxesWrite9, mailboxesWrite10, 
                            mailboxesWrite11, mailboxesWrite12, 
                            mailboxesWrite13, mailboxesRead1, mailboxesWrite14, 
                            decidedWrite, decidedWrite0, decidedWrite1, 
                            decidedWrite2, decidedWrite3, b, s, elected, pVal, 
                            promises, accepts_, resp, idx, maxBal, aidx, hVal, 
                            msg_, decidedLocal, accepts, cnt, j, entry, msg >>

loop1(self) == /\ pc[self] = "loop1"
               /\ IF (idx[self]) <= ((NUM_PROPOSERS) + ((NUM_ACCEPTORS) - (1)))
                     THEN /\ mailboxesWrite' = [network EXCEPT ![idx[self]] = Append(network[idx[self]], [type |-> PROPOSE_MSG, bal |-> b[self], sender |-> self, slot |-> s[self], val |-> v[self]])]
                          /\ idx' = [idx EXCEPT ![self] = (idx[self]) + (1)]
                          /\ mailboxesWrite0' = mailboxesWrite'
                          /\ network' = mailboxesWrite0'
                          /\ pc' = [pc EXCEPT ![self] = "loop1"]
                     ELSE /\ idx' = [idx EXCEPT ![self] = NUM_PROPOSERS]
                          /\ mailboxesWrite0' = network
                          /\ network' = mailboxesWrite0'
                          /\ pc' = [pc EXCEPT ![self] = "search1"]
                          /\ UNCHANGED mailboxesWrite
               /\ UNCHANGED << mailboxesRead, mailboxesWrite1, mailboxesWrite2, 
                               mailboxesWrite3, mailboxesWrite4, 
                               mailboxesWrite5, mailboxesWrite6, 
                               mailboxesWrite7, mailboxesRead0, 
                               mailboxesWrite8, mailboxesWrite9, 
                               mailboxesWrite10, mailboxesWrite11, 
                               mailboxesWrite12, mailboxesWrite13, 
                               mailboxesRead1, mailboxesWrite14, decidedWrite, 
                               decidedWrite0, decidedWrite1, decidedWrite2, 
                               decidedWrite3, b, s, elected, pVal, max, j_, 
                               entry_, promises, accepts_, v, resp, maxBal, 
                               aidx, hVal, msg_, decidedLocal, accepts, cnt, j, 
                               entry, msg >>

search1(self) == /\ pc[self] = "search1"
                 /\ IF (((accepts_[self]) * (2)) < (Cardinality(Acceptor))) /\ (elected[self])
                       THEN /\ (Len(network[self])) > (0)
                            /\ LET msg0 == Head(network[self]) IN
                                 /\ mailboxesWrite' = [network EXCEPT ![self] = Tail(network[self])]
                                 /\ mailboxesRead' = msg0
                            /\ resp' = [resp EXCEPT ![self] = mailboxesRead']
                            /\ IF ((resp'[self]).type) = (ACCEPT_MSG)
                                  THEN /\ network' = mailboxesWrite'
                                       /\ pc' = [pc EXCEPT ![self] = "P6"]
                                  ELSE /\ pc' = [pc EXCEPT ![self] = "search1"]
                                       /\ UNCHANGED network
                       ELSE /\ pc' = [pc EXCEPT ![self] = "P7"]
                            /\ UNCHANGED << network, mailboxesWrite, 
                                            mailboxesRead, resp >>
                 /\ UNCHANGED << mailboxesWrite0, mailboxesWrite1, 
                                 mailboxesWrite2, mailboxesWrite3, 
                                 mailboxesWrite4, mailboxesWrite5, 
                                 mailboxesWrite6, mailboxesWrite7, 
                                 mailboxesRead0, mailboxesWrite8, 
                                 mailboxesWrite9, mailboxesWrite10, 
                                 mailboxesWrite11, mailboxesWrite12, 
                                 mailboxesWrite13, mailboxesRead1, 
                                 mailboxesWrite14, decidedWrite, decidedWrite0, 
                                 decidedWrite1, decidedWrite2, decidedWrite3, 
                                 b, s, elected, pVal, max, j_, entry_, 
                                 promises, accepts_, v, idx, maxBal, aidx, 
                                 hVal, msg_, decidedLocal, accepts, cnt, j, 
                                 entry, msg >>

P6(self) == /\ pc[self] = "P6"
            /\ IF ((((resp[self]).bal) > (b[self])) \/ (((resp[self]).slot) # (s[self]))) \/ (((resp[self]).val) # (v[self]))
                  THEN /\ elected' = [elected EXCEPT ![self] = FALSE]
                       /\ pc' = [pc EXCEPT ![self] = "search1"]
                       /\ UNCHANGED accepts_
                  ELSE /\ accepts_' = [accepts_ EXCEPT ![self] = (accepts_[self]) + (1)]
                       /\ pc' = [pc EXCEPT ![self] = "search1"]
                       /\ UNCHANGED elected
            /\ UNCHANGED << network, mailboxesWrite, mailboxesWrite0, 
                            mailboxesRead, mailboxesWrite1, mailboxesWrite2, 
                            mailboxesWrite3, mailboxesWrite4, mailboxesWrite5, 
                            mailboxesWrite6, mailboxesWrite7, mailboxesRead0, 
                            mailboxesWrite8, mailboxesWrite9, mailboxesWrite10, 
                            mailboxesWrite11, mailboxesWrite12, 
                            mailboxesWrite13, mailboxesRead1, mailboxesWrite14, 
                            decidedWrite, decidedWrite0, decidedWrite1, 
                            decidedWrite2, decidedWrite3, b, s, pVal, max, j_, 
                            entry_, promises, v, resp, idx, maxBal, aidx, hVal, 
                            msg_, decidedLocal, accepts, cnt, j, entry, msg >>

P7(self) == /\ pc[self] = "P7"
            /\ IF elected[self]
                  THEN /\ pc' = [pc EXCEPT ![self] = "P8"]
                  ELSE /\ pc' = [pc EXCEPT ![self] = "P"]
            /\ UNCHANGED << network, mailboxesWrite, mailboxesWrite0, 
                            mailboxesRead, mailboxesWrite1, mailboxesWrite2, 
                            mailboxesWrite3, mailboxesWrite4, mailboxesWrite5, 
                            mailboxesWrite6, mailboxesWrite7, mailboxesRead0, 
                            mailboxesWrite8, mailboxesWrite9, mailboxesWrite10, 
                            mailboxesWrite11, mailboxesWrite12, 
                            mailboxesWrite13, mailboxesRead1, mailboxesWrite14, 
                            decidedWrite, decidedWrite0, decidedWrite1, 
                            decidedWrite2, decidedWrite3, b, s, elected, pVal, 
                            max, j_, entry_, promises, accepts_, v, resp, idx, 
                            maxBal, aidx, hVal, msg_, decidedLocal, accepts, 
                            cnt, j, entry, msg >>

P8(self) == /\ pc[self] = "P8"
            /\ s' = [s EXCEPT ![self] = (s[self]) + (1)]
            /\ pc' = [pc EXCEPT ![self] = "P"]
            /\ UNCHANGED << network, mailboxesWrite, mailboxesWrite0, 
                            mailboxesRead, mailboxesWrite1, mailboxesWrite2, 
                            mailboxesWrite3, mailboxesWrite4, mailboxesWrite5, 
                            mailboxesWrite6, mailboxesWrite7, mailboxesRead0, 
                            mailboxesWrite8, mailboxesWrite9, mailboxesWrite10, 
                            mailboxesWrite11, mailboxesWrite12, 
                            mailboxesWrite13, mailboxesRead1, mailboxesWrite14, 
                            decidedWrite, decidedWrite0, decidedWrite1, 
                            decidedWrite2, decidedWrite3, b, elected, pVal, 
                            max, j_, entry_, promises, accepts_, v, resp, idx, 
                            maxBal, aidx, hVal, msg_, decidedLocal, accepts, 
                            cnt, j, entry, msg >>

loop3(self) == /\ pc[self] = "loop3"
               /\ IF (idx[self]) <= ((NUM_PROPOSERS) + ((NUM_ACCEPTORS) - (1)))
                     THEN /\ mailboxesWrite' = [network EXCEPT ![idx[self]] = Append(network[idx[self]], [type |-> PREPARE_MSG, bal |-> b[self], sender |-> self, slot |-> s[self], val |-> v[self]])]
                          /\ idx' = [idx EXCEPT ![self] = (idx[self]) + (1)]
                          /\ mailboxesWrite1' = mailboxesWrite'
                          /\ network' = mailboxesWrite1'
                          /\ pc' = [pc EXCEPT ![self] = "loop3"]
                          /\ UNCHANGED promises
                     ELSE /\ idx' = [idx EXCEPT ![self] = NUM_PROPOSERS]
                          /\ promises' = [promises EXCEPT ![self] = 0]
                          /\ mailboxesWrite1' = network
                          /\ network' = mailboxesWrite1'
                          /\ pc' = [pc EXCEPT ![self] = "search2"]
                          /\ UNCHANGED mailboxesWrite
               /\ UNCHANGED << mailboxesWrite0, mailboxesRead, mailboxesWrite2, 
                               mailboxesWrite3, mailboxesWrite4, 
                               mailboxesWrite5, mailboxesWrite6, 
                               mailboxesWrite7, mailboxesRead0, 
                               mailboxesWrite8, mailboxesWrite9, 
                               mailboxesWrite10, mailboxesWrite11, 
                               mailboxesWrite12, mailboxesWrite13, 
                               mailboxesRead1, mailboxesWrite14, decidedWrite, 
                               decidedWrite0, decidedWrite1, decidedWrite2, 
                               decidedWrite3, b, s, elected, pVal, max, j_, 
                               entry_, accepts_, v, resp, maxBal, aidx, hVal, 
                               msg_, decidedLocal, accepts, cnt, j, entry, msg >>

search2(self) == /\ pc[self] = "search2"
                 /\ IF ~(elected[self])
                       THEN /\ (Len(network[self])) > (0)
                            /\ LET msg1 == Head(network[self]) IN
                                 /\ mailboxesWrite' = [network EXCEPT ![self] = Tail(network[self])]
                                 /\ mailboxesRead' = msg1
                            /\ resp' = [resp EXCEPT ![self] = mailboxesRead']
                            /\ IF ((resp'[self]).type) = (PROMISE_MSG)
                                  THEN /\ pVal' = [pVal EXCEPT ![self] = (pVal[self]) \o ((resp'[self]).hv)]
                                       /\ network' = mailboxesWrite'
                                       /\ pc' = [pc EXCEPT ![self] = "P2"]
                                       /\ UNCHANGED << mailboxesWrite4, 
                                                       mailboxesWrite5 >>
                                  ELSE /\ mailboxesWrite4' = network
                                       /\ mailboxesWrite5' = mailboxesWrite4'
                                       /\ network' = mailboxesWrite5'
                                       /\ pc' = [pc EXCEPT ![self] = "search2"]
                                       /\ pVal' = pVal
                       ELSE /\ mailboxesWrite5' = network
                            /\ network' = mailboxesWrite5'
                            /\ pc' = [pc EXCEPT ![self] = "P"]
                            /\ UNCHANGED << mailboxesWrite, mailboxesRead, 
                                            mailboxesWrite4, pVal, resp >>
                 /\ UNCHANGED << mailboxesWrite0, mailboxesWrite1, 
                                 mailboxesWrite2, mailboxesWrite3, 
                                 mailboxesWrite6, mailboxesWrite7, 
                                 mailboxesRead0, mailboxesWrite8, 
                                 mailboxesWrite9, mailboxesWrite10, 
                                 mailboxesWrite11, mailboxesWrite12, 
                                 mailboxesWrite13, mailboxesRead1, 
                                 mailboxesWrite14, decidedWrite, decidedWrite0, 
                                 decidedWrite1, decidedWrite2, decidedWrite3, 
                                 b, s, elected, max, j_, entry_, promises, 
                                 accepts_, v, idx, maxBal, aidx, hVal, msg_, 
                                 decidedLocal, accepts, cnt, j, entry, msg >>

P2(self) == /\ pc[self] = "P2"
            /\ IF ((resp[self]).bal) > (b[self])
                  THEN /\ b' = [b EXCEPT ![self] = (b[self]) + (NUM_PROPOSERS)]
                       /\ pc' = [pc EXCEPT ![self] = "loop4"]
                  ELSE /\ pc' = [pc EXCEPT ![self] = "P3"]
                       /\ b' = b
            /\ UNCHANGED << network, mailboxesWrite, mailboxesWrite0, 
                            mailboxesRead, mailboxesWrite1, mailboxesWrite2, 
                            mailboxesWrite3, mailboxesWrite4, mailboxesWrite5, 
                            mailboxesWrite6, mailboxesWrite7, mailboxesRead0, 
                            mailboxesWrite8, mailboxesWrite9, mailboxesWrite10, 
                            mailboxesWrite11, mailboxesWrite12, 
                            mailboxesWrite13, mailboxesRead1, mailboxesWrite14, 
                            decidedWrite, decidedWrite0, decidedWrite1, 
                            decidedWrite2, decidedWrite3, s, elected, pVal, 
                            max, j_, entry_, promises, accepts_, v, resp, idx, 
                            maxBal, aidx, hVal, msg_, decidedLocal, accepts, 
                            cnt, j, entry, msg >>

loop4(self) == /\ pc[self] = "loop4"
               /\ IF (idx[self]) <= ((NUM_PROPOSERS) + ((NUM_ACCEPTORS) - (1)))
                     THEN /\ mailboxesWrite' = [network EXCEPT ![idx[self]] = Append(network[idx[self]], [type |-> PREPARE_MSG, bal |-> b[self], sender |-> self, slot |-> s[self], val |-> v[self]])]
                          /\ idx' = [idx EXCEPT ![self] = (idx[self]) + (1)]
                          /\ mailboxesWrite2' = mailboxesWrite'
                          /\ network' = mailboxesWrite2'
                          /\ pc' = [pc EXCEPT ![self] = "loop4"]
                     ELSE /\ idx' = [idx EXCEPT ![self] = NUM_PROPOSERS]
                          /\ mailboxesWrite2' = network
                          /\ network' = mailboxesWrite2'
                          /\ pc' = [pc EXCEPT ![self] = "search2"]
                          /\ UNCHANGED mailboxesWrite
               /\ UNCHANGED << mailboxesWrite0, mailboxesRead, mailboxesWrite1, 
                               mailboxesWrite3, mailboxesWrite4, 
                               mailboxesWrite5, mailboxesWrite6, 
                               mailboxesWrite7, mailboxesRead0, 
                               mailboxesWrite8, mailboxesWrite9, 
                               mailboxesWrite10, mailboxesWrite11, 
                               mailboxesWrite12, mailboxesWrite13, 
                               mailboxesRead1, mailboxesWrite14, decidedWrite, 
                               decidedWrite0, decidedWrite1, decidedWrite2, 
                               decidedWrite3, b, s, elected, pVal, max, j_, 
                               entry_, promises, accepts_, v, resp, maxBal, 
                               aidx, hVal, msg_, decidedLocal, accepts, cnt, j, 
                               entry, msg >>

P3(self) == /\ pc[self] = "P3"
            /\ IF ((resp[self]).bal) = (b[self])
                  THEN /\ promises' = [promises EXCEPT ![self] = (promises[self]) + (1)]
                       /\ pc' = [pc EXCEPT ![self] = "P4"]
                  ELSE /\ pc' = [pc EXCEPT ![self] = "search2"]
                       /\ UNCHANGED promises
            /\ UNCHANGED << network, mailboxesWrite, mailboxesWrite0, 
                            mailboxesRead, mailboxesWrite1, mailboxesWrite2, 
                            mailboxesWrite3, mailboxesWrite4, mailboxesWrite5, 
                            mailboxesWrite6, mailboxesWrite7, mailboxesRead0, 
                            mailboxesWrite8, mailboxesWrite9, mailboxesWrite10, 
                            mailboxesWrite11, mailboxesWrite12, 
                            mailboxesWrite13, mailboxesRead1, mailboxesWrite14, 
                            decidedWrite, decidedWrite0, decidedWrite1, 
                            decidedWrite2, decidedWrite3, b, s, elected, pVal, 
                            max, j_, entry_, accepts_, v, resp, idx, maxBal, 
                            aidx, hVal, msg_, decidedLocal, accepts, cnt, j, 
                            entry, msg >>

P4(self) == /\ pc[self] = "P4"
            /\ IF ((promises[self]) * (2)) > (Cardinality(Acceptor))
                  THEN /\ elected' = [elected EXCEPT ![self] = TRUE]
                       /\ pc' = [pc EXCEPT ![self] = "search2"]
                  ELSE /\ pc' = [pc EXCEPT ![self] = "search2"]
                       /\ UNCHANGED elected
            /\ UNCHANGED << network, mailboxesWrite, mailboxesWrite0, 
                            mailboxesRead, mailboxesWrite1, mailboxesWrite2, 
                            mailboxesWrite3, mailboxesWrite4, mailboxesWrite5, 
                            mailboxesWrite6, mailboxesWrite7, mailboxesRead0, 
                            mailboxesWrite8, mailboxesWrite9, mailboxesWrite10, 
                            mailboxesWrite11, mailboxesWrite12, 
                            mailboxesWrite13, mailboxesRead1, mailboxesWrite14, 
                            decidedWrite, decidedWrite0, decidedWrite1, 
                            decidedWrite2, decidedWrite3, b, s, pVal, max, j_, 
                            entry_, promises, accepts_, v, resp, idx, maxBal, 
                            aidx, hVal, msg_, decidedLocal, accepts, cnt, j, 
                            entry, msg >>

proposer(self) == Pre(self) \/ P(self) \/ P1(self) \/ P5(self)
                     \/ loop1(self) \/ search1(self) \/ P6(self)
                     \/ P7(self) \/ P8(self) \/ loop3(self)
                     \/ search2(self) \/ P2(self) \/ loop4(self)
                     \/ P3(self) \/ P4(self)

A(self) == /\ pc[self] = "A"
           /\ IF TRUE
                 THEN /\ (Len(network[self])) > (0)
                      /\ LET msg2 == Head(network[self]) IN
                           /\ mailboxesWrite8' = [network EXCEPT ![self] = Tail(network[self])]
                           /\ mailboxesRead0' = msg2
                      /\ msg_' = [msg_ EXCEPT ![self] = mailboxesRead0']
                      /\ network' = mailboxesWrite8'
                      /\ pc' = [pc EXCEPT ![self] = "A1"]
                      /\ UNCHANGED mailboxesWrite13
                 ELSE /\ mailboxesWrite13' = network
                      /\ network' = mailboxesWrite13'
                      /\ pc' = [pc EXCEPT ![self] = "Done"]
                      /\ UNCHANGED << mailboxesRead0, mailboxesWrite8, msg_ >>
           /\ UNCHANGED << mailboxesWrite, mailboxesWrite0, mailboxesRead, 
                           mailboxesWrite1, mailboxesWrite2, mailboxesWrite3, 
                           mailboxesWrite4, mailboxesWrite5, mailboxesWrite6, 
                           mailboxesWrite7, mailboxesWrite9, mailboxesWrite10, 
                           mailboxesWrite11, mailboxesWrite12, mailboxesRead1, 
                           mailboxesWrite14, decidedWrite, decidedWrite0, 
                           decidedWrite1, decidedWrite2, decidedWrite3, b, s, 
                           elected, pVal, max, j_, entry_, promises, accepts_, 
                           v, resp, idx, maxBal, aidx, hVal, decidedLocal, 
                           accepts, cnt, j, entry, msg >>

A1(self) == /\ pc[self] = "A1"
            /\ IF (((msg_[self]).type) = (PREPARE_MSG)) /\ (((msg_[self]).bal) > (maxBal[self]))
                  THEN /\ pc' = [pc EXCEPT ![self] = "A2"]
                       /\ UNCHANGED << network, mailboxesWrite10, 
                                       mailboxesWrite11, mailboxesWrite12 >>
                  ELSE /\ IF (((msg_[self]).type) = (PROPOSE_MSG)) /\ (((msg_[self]).bal) >= (maxBal[self]))
                             THEN /\ pc' = [pc EXCEPT ![self] = "A3"]
                                  /\ UNCHANGED << network, mailboxesWrite10, 
                                                  mailboxesWrite11, 
                                                  mailboxesWrite12 >>
                             ELSE /\ IF (((msg_[self]).type) = (PROPOSE_MSG)) /\ (((msg_[self]).bal) < (maxBal[self]))
                                        THEN /\ pc' = [pc EXCEPT ![self] = "A4"]
                                             /\ UNCHANGED << network, 
                                                             mailboxesWrite10, 
                                                             mailboxesWrite11, 
                                                             mailboxesWrite12 >>
                                        ELSE /\ mailboxesWrite10' = network
                                             /\ mailboxesWrite11' = mailboxesWrite10'
                                             /\ mailboxesWrite12' = mailboxesWrite11'
                                             /\ network' = mailboxesWrite12'
                                             /\ pc' = [pc EXCEPT ![self] = "A"]
            /\ UNCHANGED << mailboxesWrite, mailboxesWrite0, mailboxesRead, 
                            mailboxesWrite1, mailboxesWrite2, mailboxesWrite3, 
                            mailboxesWrite4, mailboxesWrite5, mailboxesWrite6, 
                            mailboxesWrite7, mailboxesRead0, mailboxesWrite8, 
                            mailboxesWrite9, mailboxesWrite13, mailboxesRead1, 
                            mailboxesWrite14, decidedWrite, decidedWrite0, 
                            decidedWrite1, decidedWrite2, decidedWrite3, b, s, 
                            elected, pVal, max, j_, entry_, promises, accepts_, 
                            v, resp, idx, maxBal, aidx, hVal, msg_, 
                            decidedLocal, accepts, cnt, j, entry, msg >>

A2(self) == /\ pc[self] = "A2"
            /\ maxBal' = [maxBal EXCEPT ![self] = (msg_[self]).bal]
            /\ mailboxesWrite8' = [network EXCEPT ![(msg_[self]).sender] = Append(network[(msg_[self]).sender], [type |-> PROMISE_MSG, sender |-> self, bal |-> maxBal'[self], slot |-> (msg_[self]).slot, val |-> (msg_[self]).val, hv |-> hVal[self]])]
            /\ network' = mailboxesWrite8'
            /\ pc' = [pc EXCEPT ![self] = "A"]
            /\ UNCHANGED << mailboxesWrite, mailboxesWrite0, mailboxesRead, 
                            mailboxesWrite1, mailboxesWrite2, mailboxesWrite3, 
                            mailboxesWrite4, mailboxesWrite5, mailboxesWrite6, 
                            mailboxesWrite7, mailboxesRead0, mailboxesWrite9, 
                            mailboxesWrite10, mailboxesWrite11, 
                            mailboxesWrite12, mailboxesWrite13, mailboxesRead1, 
                            mailboxesWrite14, decidedWrite, decidedWrite0, 
                            decidedWrite1, decidedWrite2, decidedWrite3, b, s, 
                            elected, pVal, max, j_, entry_, promises, accepts_, 
                            v, resp, idx, aidx, hVal, msg_, decidedLocal, 
                            accepts, cnt, j, entry, msg >>

A3(self) == /\ pc[self] = "A3"
            /\ maxBal' = [maxBal EXCEPT ![self] = (msg_[self]).bal]
            /\ aidx' = [aidx EXCEPT ![self] = (NUM_PROPOSERS) + (NUM_ACCEPTORS)]
            /\ hVal' = [hVal EXCEPT ![self] = Append(hVal[self], [slot |-> (msg_[self]).slot, bal |-> (msg_[self]).bal, val |-> (msg_[self]).val])]
            /\ mailboxesWrite8' = [network EXCEPT ![(msg_[self]).sender] = Append(network[(msg_[self]).sender], [type |-> ACCEPT_MSG, sender |-> self, bal |-> maxBal'[self], slot |-> (msg_[self]).slot, val |-> (msg_[self]).val, hv |-> hVal'[self]])]
            /\ network' = mailboxesWrite8'
            /\ pc' = [pc EXCEPT ![self] = "loop2"]
            /\ UNCHANGED << mailboxesWrite, mailboxesWrite0, mailboxesRead, 
                            mailboxesWrite1, mailboxesWrite2, mailboxesWrite3, 
                            mailboxesWrite4, mailboxesWrite5, mailboxesWrite6, 
                            mailboxesWrite7, mailboxesRead0, mailboxesWrite9, 
                            mailboxesWrite10, mailboxesWrite11, 
                            mailboxesWrite12, mailboxesWrite13, mailboxesRead1, 
                            mailboxesWrite14, decidedWrite, decidedWrite0, 
                            decidedWrite1, decidedWrite2, decidedWrite3, b, s, 
                            elected, pVal, max, j_, entry_, promises, accepts_, 
                            v, resp, idx, msg_, decidedLocal, accepts, cnt, j, 
                            entry, msg >>

loop2(self) == /\ pc[self] = "loop2"
               /\ IF (aidx[self]) <= (((NUM_PROPOSERS) + (NUM_ACCEPTORS)) + ((NUM_LEARNERS) - (1)))
                     THEN /\ mailboxesWrite8' = [network EXCEPT ![aidx[self]] = Append(network[aidx[self]], [type |-> ACCEPT_MSG, sender |-> self, bal |-> maxBal[self], slot |-> (msg_[self]).slot, val |-> (msg_[self]).val, hv |-> hVal[self]])]
                          /\ aidx' = [aidx EXCEPT ![self] = (aidx[self]) + (1)]
                          /\ mailboxesWrite9' = mailboxesWrite8'
                          /\ network' = mailboxesWrite9'
                          /\ pc' = [pc EXCEPT ![self] = "loop2"]
                     ELSE /\ mailboxesWrite9' = network
                          /\ network' = mailboxesWrite9'
                          /\ pc' = [pc EXCEPT ![self] = "A"]
                          /\ UNCHANGED << mailboxesWrite8, aidx >>
               /\ UNCHANGED << mailboxesWrite, mailboxesWrite0, mailboxesRead, 
                               mailboxesWrite1, mailboxesWrite2, 
                               mailboxesWrite3, mailboxesWrite4, 
                               mailboxesWrite5, mailboxesWrite6, 
                               mailboxesWrite7, mailboxesRead0, 
                               mailboxesWrite10, mailboxesWrite11, 
                               mailboxesWrite12, mailboxesWrite13, 
                               mailboxesRead1, mailboxesWrite14, decidedWrite, 
                               decidedWrite0, decidedWrite1, decidedWrite2, 
                               decidedWrite3, b, s, elected, pVal, max, j_, 
                               entry_, promises, accepts_, v, resp, idx, 
                               maxBal, hVal, msg_, decidedLocal, accepts, cnt, 
                               j, entry, msg >>

A4(self) == /\ pc[self] = "A4"
            /\ mailboxesWrite8' = [network EXCEPT ![(msg_[self]).sender] = Append(network[(msg_[self]).sender], [type |-> ACCEPT_MSG, sender |-> self, bal |-> maxBal[self], slot |-> (msg_[self]).slot, val |-> (msg_[self]).val, hv |-> hVal[self]])]
            /\ network' = mailboxesWrite8'
            /\ pc' = [pc EXCEPT ![self] = "A"]
            /\ UNCHANGED << mailboxesWrite, mailboxesWrite0, mailboxesRead, 
                            mailboxesWrite1, mailboxesWrite2, mailboxesWrite3, 
                            mailboxesWrite4, mailboxesWrite5, mailboxesWrite6, 
                            mailboxesWrite7, mailboxesRead0, mailboxesWrite9, 
                            mailboxesWrite10, mailboxesWrite11, 
                            mailboxesWrite12, mailboxesWrite13, mailboxesRead1, 
                            mailboxesWrite14, decidedWrite, decidedWrite0, 
                            decidedWrite1, decidedWrite2, decidedWrite3, b, s, 
                            elected, pVal, max, j_, entry_, promises, accepts_, 
                            v, resp, idx, maxBal, aidx, hVal, msg_, 
                            decidedLocal, accepts, cnt, j, entry, msg >>

acceptor(self) == A(self) \/ A1(self) \/ A2(self) \/ A3(self)
                     \/ loop2(self) \/ A4(self)

L(self) == /\ pc[self] = "L"
           /\ IF TRUE
                 THEN /\ (Len(network[self])) > (0)
                      /\ LET msg3 == Head(network[self]) IN
                           /\ mailboxesWrite14' = [network EXCEPT ![self] = Tail(network[self])]
                           /\ mailboxesRead1' = msg3
                      /\ msg' = [msg EXCEPT ![self] = mailboxesRead1']
                      /\ network' = mailboxesWrite14'
                      /\ pc' = [pc EXCEPT ![self] = "L1"]
                      /\ UNCHANGED << decidedWrite3, decidedLocal >>
                 ELSE /\ decidedWrite3' = decidedLocal[self]
                      /\ decidedLocal' = [decidedLocal EXCEPT ![self] = decidedWrite3']
                      /\ pc' = [pc EXCEPT ![self] = "Done"]
                      /\ UNCHANGED << network, mailboxesRead1, 
                                      mailboxesWrite14, msg >>
           /\ UNCHANGED << mailboxesWrite, mailboxesWrite0, mailboxesRead, 
                           mailboxesWrite1, mailboxesWrite2, mailboxesWrite3, 
                           mailboxesWrite4, mailboxesWrite5, mailboxesWrite6, 
                           mailboxesWrite7, mailboxesRead0, mailboxesWrite8, 
                           mailboxesWrite9, mailboxesWrite10, mailboxesWrite11, 
                           mailboxesWrite12, mailboxesWrite13, decidedWrite, 
                           decidedWrite0, decidedWrite1, decidedWrite2, b, s, 
                           elected, pVal, max, j_, entry_, promises, accepts_, 
                           v, resp, idx, maxBal, aidx, hVal, msg_, accepts, 
                           cnt, j, entry >>

L1(self) == /\ pc[self] = "L1"
            /\ IF ((msg[self]).type) = (ACCEPT_MSG)
                  THEN /\ accepts' = [accepts EXCEPT ![self] = Append(accepts[self], msg[self])]
                       /\ j' = [j EXCEPT ![self] = 1]
                       /\ cnt' = [cnt EXCEPT ![self] = 0]
                       /\ pc' = [pc EXCEPT ![self] = "L2"]
                       /\ UNCHANGED << decidedWrite2, decidedLocal >>
                  ELSE /\ decidedWrite2' = decidedLocal[self]
                       /\ decidedLocal' = [decidedLocal EXCEPT ![self] = decidedWrite2']
                       /\ pc' = [pc EXCEPT ![self] = "L"]
                       /\ UNCHANGED << accepts, cnt, j >>
            /\ UNCHANGED << network, mailboxesWrite, mailboxesWrite0, 
                            mailboxesRead, mailboxesWrite1, mailboxesWrite2, 
                            mailboxesWrite3, mailboxesWrite4, mailboxesWrite5, 
                            mailboxesWrite6, mailboxesWrite7, mailboxesRead0, 
                            mailboxesWrite8, mailboxesWrite9, mailboxesWrite10, 
                            mailboxesWrite11, mailboxesWrite12, 
                            mailboxesWrite13, mailboxesRead1, mailboxesWrite14, 
                            decidedWrite, decidedWrite0, decidedWrite1, 
                            decidedWrite3, b, s, elected, pVal, max, j_, 
                            entry_, promises, accepts_, v, resp, idx, maxBal, 
                            aidx, hVal, msg_, entry, msg >>

L2(self) == /\ pc[self] = "L2"
            /\ IF (j[self]) <= (Len(accepts[self]))
                  THEN /\ entry' = [entry EXCEPT ![self] = accepts[self][j[self]]]
                       /\ IF ((((entry'[self]).slot) = ((msg[self]).slot)) /\ (((entry'[self]).bal) = ((msg[self]).bal))) /\ (((entry'[self]).val) = ((msg[self]).val))
                             THEN /\ cnt' = [cnt EXCEPT ![self] = (cnt[self]) + (1)]
                             ELSE /\ TRUE
                                  /\ cnt' = cnt
                       /\ j' = [j EXCEPT ![self] = (j[self]) + (1)]
                       /\ decidedWrite1' = decidedLocal[self]
                       /\ decidedLocal' = [decidedLocal EXCEPT ![self] = decidedWrite1']
                       /\ pc' = [pc EXCEPT ![self] = "L2"]
                       /\ UNCHANGED << decidedWrite, decidedWrite0 >>
                  ELSE /\ IF ((cnt[self]) * (2)) > (Cardinality(Acceptor))
                             THEN /\ decidedWrite' = [decidedLocal[self] EXCEPT ![(msg[self]).slot] = (decidedLocal[self][(msg[self]).slot]) \union ({(msg[self]).val})]
                                  /\ decidedWrite0' = decidedWrite'
                                  /\ decidedWrite1' = decidedWrite0'
                                  /\ decidedLocal' = [decidedLocal EXCEPT ![self] = decidedWrite1']
                                  /\ pc' = [pc EXCEPT ![self] = "L"]
                             ELSE /\ decidedWrite0' = decidedLocal[self]
                                  /\ decidedWrite1' = decidedWrite0'
                                  /\ decidedLocal' = [decidedLocal EXCEPT ![self] = decidedWrite1']
                                  /\ pc' = [pc EXCEPT ![self] = "L"]
                                  /\ UNCHANGED decidedWrite
                       /\ UNCHANGED << cnt, j, entry >>
            /\ UNCHANGED << network, mailboxesWrite, mailboxesWrite0, 
                            mailboxesRead, mailboxesWrite1, mailboxesWrite2, 
                            mailboxesWrite3, mailboxesWrite4, mailboxesWrite5, 
                            mailboxesWrite6, mailboxesWrite7, mailboxesRead0, 
                            mailboxesWrite8, mailboxesWrite9, mailboxesWrite10, 
                            mailboxesWrite11, mailboxesWrite12, 
                            mailboxesWrite13, mailboxesRead1, mailboxesWrite14, 
                            decidedWrite2, decidedWrite3, b, s, elected, pVal, 
                            max, j_, entry_, promises, accepts_, v, resp, idx, 
                            maxBal, aidx, hVal, msg_, accepts, msg >>

learner(self) == L(self) \/ L1(self) \/ L2(self)

Next == (\E self \in Proposer: proposer(self))
           \/ (\E self \in Acceptor: acceptor(self))
           \/ (\E self \in Learner: learner(self))
           \/ (* Disjunct to prevent deadlock on termination *)
              ((\A self \in ProcSet: pc[self] = "Done") /\ UNCHANGED vars)

Spec == /\ Init /\ [][Next]_vars
        /\ \A self \in Proposer : WF_vars(proposer(self))
        /\ \A self \in Acceptor : WF_vars(acceptor(self))
        /\ \A self \in Learner : WF_vars(learner(self))

Termination == <>(\A self \in ProcSet: pc[self] = "Done")

\* END TRANSLATION


\*\*  No acceptor could have finalized/decided 2 different vals for same slot
\*\* check the two below as invariant
Agreement == \A a1,a2 \in Learner:
              \A k \in Slots: Cardinality(decidedLocal[a1][k])=1
                           /\ Cardinality(decidedLocal[a2][k])=1 => decidedLocal[a1][k]=decidedLocal[a2][k]

Agreement2 == \A i \in Learner:
               \A k \in 1..NUM_SLOTS: Cardinality(decidedLocal[i][k]) <=1


\* \* Short cut for the above

Agreement3 == \A i \in Learner:
               \A k \in 1..NUM_SLOTS: Cardinality(decidedLocal[i][k]) <=1


\* Of course this is violated! Don't check this as invariant
No2Leaders == \A i1, i2 \in Proposer : elected[i1] /\ elected[i2] => i1 = i2

\* Agreement ==
\*    \A i,j \in Acceptor :
\*        (   accepted[i] \subseteq accepted[j]
\*         \/ accepted[j] \subseteq accepted[i] )
=========================================================
