------------------------------- MODULE proxy -------------------------------

EXTENDS Naturals, Sequences, TLC, FiniteSets

CONSTANT NUM_SERVERS
CONSTANT NUM_CLIENTS
CONSTANT EXPLORE_FAIL

ASSUME NUM_SERVERS > 0 /\ NUM_CLIENTS > 0

(********************

--mpcal proxy {
    define {
        FAIL == 100
        NUM_NODES == NUM_SERVERS + NUM_CLIENTS + 1

        ProxyID == NUM_NODES

        REQ_MSG_TYP == 1
        RESP_MSG_TYP == 2
        PROXY_REQ_MSG_TYP == 3
        PROXY_RESP_MSG_TYP == 4

        NODE_SET == 1..NUM_NODES
        SERVER_SET == 1..NUM_SERVERS
        CLIENT_SET == (NUM_SERVERS+1)..(NUM_SERVERS+NUM_CLIENTS)

        MSG_TYP_SET == {REQ_MSG_TYP, RESP_MSG_TYP, PROXY_REQ_MSG_TYP, PROXY_RESP_MSG_TYP}

        MSG_ID_BOUND == 2
    }

    macro mayFail(selfID, netEnabled) {
        if (EXPLORE_FAIL) {
            either { skip; } or {
                netEnabled[selfID, PROXY_REQ_MSG_TYP] := FALSE;
                goto failLabel;
            };
        };
    }

    mapping macro ReliableFIFOLink {
        read {
            assert $variable.enabled;
            await Len($variable.queue) > 0;
            with (readMsg = Head($variable.queue)) {
                $variable := [queue |-> Tail($variable.queue), enabled |-> $variable.enabled];
                yield readMsg;
            };
        }

        write {
            await $variable.enabled;
            yield [queue |-> Append($variable.queue, $value), enabled |-> $variable.enabled];
        }
    }

    mapping macro NetworkToggle {
        read { yield $variable.enabled; }

        write {
            yield [queue |-> $variable.queue, enabled |-> $value];
        }
    }

    mapping macro PerfectFD {
        read {
            yield $variable;
        }

        write { yield $value; }
    }

    mapping macro PracticalFD {
        read {
            if ($variable = FALSE) { \* process is alive
                either { yield TRUE; } or { yield FALSE; }; \* no accuracy guarantee
            } else {
                yield $variable; \* (eventual) completeness
            };
        }

        write { yield $value; }
    }

    archetype AProxy(ref net[_], ref fd[_])
    variables
        msg, proxyMsg, idx, resp, proxyResp;
    {
    proxyLoop:
        while(TRUE) {
        rcvMsgFromClient:
            msg := net[<<ProxyID, REQ_MSG_TYP>>];

        proxyMsg:
            assert(msg.to = ProxyID /\ msg.typ = REQ_MSG_TYP);
            proxyResp := [from |-> ProxyID, to |-> msg.from, body |-> FAIL, 
                          id |-> msg.id, typ |-> PROXY_RESP_MSG_TYP];
            idx := 1;
            serversLoop:
                while (idx <= NUM_SERVERS) {
                proxySendMsg:
                    either {
                        proxyMsg := [from |-> ProxyID, to |-> idx, body |-> msg.body, 
                                     id |-> msg.id, typ |-> PROXY_REQ_MSG_TYP];
                        net[<<proxyMsg.to, PROXY_REQ_MSG_TYP>>] := proxyMsg;
                    } or {
                        await fd[idx];
                        idx := idx + 1;
                        goto serversLoop;
                    };
            
                proxyRcvMsg:
                    either {
                        with (tmp = net[<<ProxyID, PROXY_RESP_MSG_TYP>>]) {
                            if (tmp.from # idx \/ tmp.id # msg.id) {
                                goto proxyRcvMsg;
                            } else {
                                proxyResp := tmp;
                                assert(
                                    /\ proxyResp.to = ProxyID
                                    /\ proxyResp.from = idx
                                    /\ proxyResp.id = msg.id
                                    /\ proxyResp.typ = PROXY_RESP_MSG_TYP
                                );
                                goto sendMsgToClient;
                            };
                        };
                    } or {
                        await fd[idx];
                        idx := idx + 1;
                    };
                };
        
        sendMsgToClient:
            resp := [from |-> ProxyID, to |-> msg.from, body |-> proxyResp.body, 
                     id |-> msg.id, typ |-> RESP_MSG_TYP];
            net[<<resp.to, resp.typ>>] := resp;
        };
    }

    archetype AServer(ref net[_], ref netEnabled[_], ref fd[_])
    variables
        msg, resp;
    {
    serverLoop:
        while (TRUE) {
            mayFail(self, netEnabled);

        serverRcvMsg:
            msg := net[<<self, PROXY_REQ_MSG_TYP>>];
            assert(
                /\ msg.to = self
                /\ msg.from = ProxyID
                /\ msg.typ = PROXY_REQ_MSG_TYP
            );
            mayFail(self, netEnabled);

        serverSendMsg:
            resp := [from |-> self, to |-> msg.from, body |-> self, 
                     id |-> msg.id, typ |-> PROXY_RESP_MSG_TYP];
            net[<<resp.to, resp.typ>>] := resp;
            mayFail(self, netEnabled);
        };

    failLabel:
        fd[self] := TRUE;
    }

    archetype AClient(ref net[_], ref output)
    variables
        req, resp, reqId = 0;
    {
    clientLoop:
        while (TRUE) {
        clientSendReq:
            req := [from |-> self, to |-> ProxyID, body |-> self, 
                    id |-> reqId, typ |-> REQ_MSG_TYP];
            net[<<req.to, req.typ>>] := req;
            print <<"CLIENT START", req>>;

        clientRcvResp:
            resp := net[<<self, RESP_MSG_TYP>>];
            assert(
                /\ resp.to = self
                /\ resp.id = reqId
                /\ resp.from = ProxyID
                /\ resp.typ = RESP_MSG_TYP
            );
            print <<"CLIENT RESP", resp>>;
            reqId := (reqId + 1) % MSG_ID_BOUND;
            output := resp;
        }
    }

    variables
        network = [id \in NODE_SET, typ \in MSG_TYP_SET |-> [queue |-> <<>>, enabled |-> TRUE]];
        fd = [id \in NODE_SET |-> FALSE];
        output = <<>>;
    
    fair process (Proxy = ProxyID) == instance AProxy(ref network[_], ref fd[_])
        mapping network[_] via ReliableFIFOLink
        mapping fd[_] via PerfectFD;

    fair process (Server \in SERVER_SET) == instance AServer(ref network[_], ref network[_], ref fd[_])
        mapping @1[_] via ReliableFIFOLink
        mapping @2[_] via NetworkToggle
        mapping @3[_] via PerfectFD;

    fair process (Client \in CLIENT_SET) == instance AClient(ref network[_], ref output)
        mapping network[_] via ReliableFIFOLink;
}

\* BEGIN PLUSCAL TRANSLATION
--algorithm proxy {
  variables network = [id \in NODE_SET, typ \in MSG_TYP_SET |-> [queue |-> <<>>, enabled |-> TRUE]]; fd = [id \in NODE_SET |-> FALSE]; output = <<>>;
  define{
    FAIL == 100
    NUM_NODES == ((NUM_SERVERS) + (NUM_CLIENTS)) + (1)
    ProxyID == NUM_NODES
    REQ_MSG_TYP == 1
    RESP_MSG_TYP == 2
    PROXY_REQ_MSG_TYP == 3
    PROXY_RESP_MSG_TYP == 4
    NODE_SET == (1) .. (NUM_NODES)
    SERVER_SET == (1) .. (NUM_SERVERS)
    CLIENT_SET == ((NUM_SERVERS) + (1)) .. ((NUM_SERVERS) + (NUM_CLIENTS))
    MSG_TYP_SET == {REQ_MSG_TYP, RESP_MSG_TYP, PROXY_REQ_MSG_TYP, PROXY_RESP_MSG_TYP}
    MSG_ID_BOUND == 2
  }
  
  fair process (Proxy = ProxyID)
    variables msg; proxyMsg; idx; resp; proxyResp;
  {
    proxyLoop:
      if(TRUE) {
        goto rcvMsgFromClient;
      } else {
        goto Done;
      };
    rcvMsgFromClient:
      assert ((network)[<<ProxyID, REQ_MSG_TYP>>]).enabled;
      await (Len(((network)[<<ProxyID, REQ_MSG_TYP>>]).queue)) > (0);
      with (readMsg0 = Head(((network)[<<ProxyID, REQ_MSG_TYP>>]).queue)) {
        network := [network EXCEPT ![<<ProxyID, REQ_MSG_TYP>>] = [queue |-> Tail(((network)[<<ProxyID, REQ_MSG_TYP>>]).queue), enabled |-> ((network)[<<ProxyID, REQ_MSG_TYP>>]).enabled]];
        with (yielded_net3 = readMsg0) {
          msg := yielded_net3;
          goto proxyMsg;
        };
      };
    proxyMsg:
      assert (((msg).to) = (ProxyID)) /\ (((msg).typ) = (REQ_MSG_TYP));
      proxyResp := [from |-> ProxyID, to |-> (msg).from, body |-> FAIL, id |-> (msg).id, typ |-> PROXY_RESP_MSG_TYP];
      idx := 1;
      goto serversLoop;
    serversLoop:
      if((idx) <= (NUM_SERVERS)) {
        goto proxySendMsg;
      } else {
        goto sendMsgToClient;
      };
    proxySendMsg:
      either {
        proxyMsg := [from |-> ProxyID, to |-> idx, body |-> (msg).body, id |-> (msg).id, typ |-> PROXY_REQ_MSG_TYP];
        with (value7 = proxyMsg) {
          await ((network)[<<(proxyMsg).to, PROXY_REQ_MSG_TYP>>]).enabled;
          network := [network EXCEPT ![<<(proxyMsg).to, PROXY_REQ_MSG_TYP>>] = [queue |-> Append(((network)[<<(proxyMsg).to, PROXY_REQ_MSG_TYP>>]).queue, value7), enabled |-> ((network)[<<(proxyMsg).to, PROXY_REQ_MSG_TYP>>]).enabled]];
          goto proxyRcvMsg;
        };
      } or {
        with (yielded_fd1 = (fd)[idx]) {
          await yielded_fd1;
          idx := (idx) + (1);
          goto serversLoop;
        };
      };
    proxyRcvMsg:
      either {
        assert ((network)[<<ProxyID, PROXY_RESP_MSG_TYP>>]).enabled;
        await (Len(((network)[<<ProxyID, PROXY_RESP_MSG_TYP>>]).queue)) > (0);
        with (readMsg = Head(((network)[<<ProxyID, PROXY_RESP_MSG_TYP>>]).queue)) {
          network := [network EXCEPT ![<<ProxyID, PROXY_RESP_MSG_TYP>>] = [queue |-> Tail(((network)[<<ProxyID, PROXY_RESP_MSG_TYP>>]).queue), enabled |-> ((network)[<<ProxyID, PROXY_RESP_MSG_TYP>>]).enabled]];
          with (yielded_net0 = readMsg) {
            with (tmp = yielded_net0) {
              if((((tmp).from) # (idx)) \/ (((tmp).id) # ((msg).id))) {
                goto proxyRcvMsg;
              } else {
                proxyResp := tmp;
                assert (((((proxyResp).to) = (ProxyID)) /\ (((proxyResp).from) = (idx))) /\ (((proxyResp).id) = ((msg).id))) /\ (((proxyResp).typ) = (PROXY_RESP_MSG_TYP));
                goto sendMsgToClient;
              };
            };
          };
        };
      } or {
        with (yielded_fd00 = (fd)[idx]) {
          await yielded_fd00;
          idx := (idx) + (1);
          goto serversLoop;
        };
      };
    sendMsgToClient:
      resp := [from |-> ProxyID, to |-> (msg).from, body |-> (proxyResp).body, id |-> (msg).id, typ |-> RESP_MSG_TYP];
      with (value00 = resp) {
        await ((network)[<<(resp).to, (resp).typ>>]).enabled;
        network := [network EXCEPT ![<<(resp).to, (resp).typ>>] = [queue |-> Append(((network)[<<(resp).to, (resp).typ>>]).queue, value00), enabled |-> ((network)[<<(resp).to, (resp).typ>>]).enabled]];
        goto proxyLoop;
      };
  }
  
  fair process (Server \in SERVER_SET)
    variables msg; resp;
  {
    serverLoop:
      if(TRUE) {
        if(EXPLORE_FAIL) {
          either {
            skip;
            goto serverRcvMsg;
          } or {
            with (value10 = FALSE) {
              network := [network EXCEPT ![self, PROXY_REQ_MSG_TYP] = [queue |-> ((network)[self, PROXY_REQ_MSG_TYP]).queue, enabled |-> value10]];
              goto failLabel;
            };
          };
        } else {
          goto serverRcvMsg;
        };
      } else {
        goto failLabel;
      };
    serverRcvMsg:
      assert ((network)[<<self, PROXY_REQ_MSG_TYP>>]).enabled;
      await (Len(((network)[<<self, PROXY_REQ_MSG_TYP>>]).queue)) > (0);
      with (readMsg1 = Head(((network)[<<self, PROXY_REQ_MSG_TYP>>]).queue)) {
        with (network0 = [network EXCEPT ![<<self, PROXY_REQ_MSG_TYP>>] = [queue |-> Tail(((network)[<<self, PROXY_REQ_MSG_TYP>>]).queue), enabled |-> ((network)[<<self, PROXY_REQ_MSG_TYP>>]).enabled]]) {
          with (yielded_net10 = readMsg1) {
            msg := yielded_net10;
            assert ((((msg).to) = (self)) /\ (((msg).from) = (ProxyID))) /\ (((msg).typ) = (PROXY_REQ_MSG_TYP));
            if(EXPLORE_FAIL) {
              either {
                skip;
                network := network0;
                goto serverSendMsg;
              } or {
                with (value20 = FALSE) {
                  network := [network0 EXCEPT ![self, PROXY_REQ_MSG_TYP] = [queue |-> ((network0)[self, PROXY_REQ_MSG_TYP]).queue, enabled |-> value20]];
                  goto failLabel;
                };
              };
            } else {
              network := network0;
              goto serverSendMsg;
            };
          };
        };
      };
    serverSendMsg:
      resp := [from |-> self, to |-> (msg).from, body |-> self, id |-> (msg).id, typ |-> PROXY_RESP_MSG_TYP];
      with (value30 = resp) {
        await ((network)[<<(resp).to, (resp).typ>>]).enabled;
        with (network1 = [network EXCEPT ![<<(resp).to, (resp).typ>>] = [queue |-> Append(((network)[<<(resp).to, (resp).typ>>]).queue, value30), enabled |-> ((network)[<<(resp).to, (resp).typ>>]).enabled]]) {
          if(EXPLORE_FAIL) {
            either {
              skip;
              network := network1;
              goto serverLoop;
            } or {
              with (value40 = FALSE) {
                network := [network1 EXCEPT ![self, PROXY_REQ_MSG_TYP] = [queue |-> ((network1)[self, PROXY_REQ_MSG_TYP]).queue, enabled |-> value40]];
                goto failLabel;
              };
            };
          } else {
            network := network1;
            goto serverLoop;
          };
        };
      };
    failLabel:
      with (value50 = TRUE) {
        fd := [fd EXCEPT ![self] = value50];
        goto Done;
      };
  }
  
  fair process (Client \in CLIENT_SET)
    variables req; resp; reqId = 0;
  {
    clientLoop:
      if(TRUE) {
        goto clientSendReq;
      } else {
        goto Done;
      };
    clientSendReq:
      req := [from |-> self, to |-> ProxyID, body |-> self, id |-> reqId, typ |-> REQ_MSG_TYP];
      with (value60 = req) {
        await ((network)[<<(req).to, (req).typ>>]).enabled;
        network := [network EXCEPT ![<<(req).to, (req).typ>>] = [queue |-> Append(((network)[<<(req).to, (req).typ>>]).queue, value60), enabled |-> ((network)[<<(req).to, (req).typ>>]).enabled]];
        print <<"CLIENT START", req>>;
        goto clientRcvResp;
      };
    clientRcvResp:
      assert ((network)[<<self, RESP_MSG_TYP>>]).enabled;
      await (Len(((network)[<<self, RESP_MSG_TYP>>]).queue)) > (0);
      with (readMsg2 = Head(((network)[<<self, RESP_MSG_TYP>>]).queue)) {
        network := [network EXCEPT ![<<self, RESP_MSG_TYP>>] = [queue |-> Tail(((network)[<<self, RESP_MSG_TYP>>]).queue), enabled |-> ((network)[<<self, RESP_MSG_TYP>>]).enabled]];
        with (yielded_net20 = readMsg2) {
          resp := yielded_net20;
          assert (((((resp).to) = (self)) /\ (((resp).id) = (reqId))) /\ (((resp).from) = (ProxyID))) /\ (((resp).typ) = (RESP_MSG_TYP));
          print <<"CLIENT RESP", resp>>;
          reqId := ((reqId) + (1)) % (MSG_ID_BOUND);
          output := resp;
          goto clientLoop;
        };
      };
  }
}

\* END PLUSCAL TRANSLATION


********************)

\* BEGIN TRANSLATION (chksum(pcal) = "e2f5b0b1" /\ chksum(tla) = "44cd1e55")
\* Label proxyMsg of process Proxy at line 253 col 7 changed to proxyMsg_
\* Process variable msg of process Proxy at line 234 col 15 changed to msg_
\* Process variable resp of process Proxy at line 234 col 35 changed to resp_
\* Process variable resp of process Server at line 313 col 20 changed to resp_S
CONSTANT defaultInitValue
VARIABLES network, fd, output, pc

(* define statement *)
FAIL == 100
NUM_NODES == ((NUM_SERVERS) + (NUM_CLIENTS)) + (1)
ProxyID == NUM_NODES
REQ_MSG_TYP == 1
RESP_MSG_TYP == 2
PROXY_REQ_MSG_TYP == 3
PROXY_RESP_MSG_TYP == 4
NODE_SET == (1) .. (NUM_NODES)
SERVER_SET == (1) .. (NUM_SERVERS)
CLIENT_SET == ((NUM_SERVERS) + (1)) .. ((NUM_SERVERS) + (NUM_CLIENTS))
MSG_TYP_SET == {REQ_MSG_TYP, RESP_MSG_TYP, PROXY_REQ_MSG_TYP, PROXY_RESP_MSG_TYP}
MSG_ID_BOUND == 2

VARIABLES msg_, proxyMsg, idx, resp_, proxyResp, msg, resp_S, req, resp, 
          reqId

vars == << network, fd, output, pc, msg_, proxyMsg, idx, resp_, proxyResp, 
           msg, resp_S, req, resp, reqId >>

ProcSet == {ProxyID} \cup (SERVER_SET) \cup (CLIENT_SET)

Init == (* Global variables *)
        /\ network = [id \in NODE_SET, typ \in MSG_TYP_SET |-> [queue |-> <<>>, enabled |-> TRUE]]
        /\ fd = [id \in NODE_SET |-> FALSE]
        /\ output = <<>>
        (* Process Proxy *)
        /\ msg_ = defaultInitValue
        /\ proxyMsg = defaultInitValue
        /\ idx = defaultInitValue
        /\ resp_ = defaultInitValue
        /\ proxyResp = defaultInitValue
        (* Process Server *)
        /\ msg = [self \in SERVER_SET |-> defaultInitValue]
        /\ resp_S = [self \in SERVER_SET |-> defaultInitValue]
        (* Process Client *)
        /\ req = [self \in CLIENT_SET |-> defaultInitValue]
        /\ resp = [self \in CLIENT_SET |-> defaultInitValue]
        /\ reqId = [self \in CLIENT_SET |-> 0]
        /\ pc = [self \in ProcSet |-> CASE self = ProxyID -> "proxyLoop"
                                        [] self \in SERVER_SET -> "serverLoop"
                                        [] self \in CLIENT_SET -> "clientLoop"]

proxyLoop == /\ pc[ProxyID] = "proxyLoop"
             /\ IF TRUE
                   THEN /\ pc' = [pc EXCEPT ![ProxyID] = "rcvMsgFromClient"]
                   ELSE /\ pc' = [pc EXCEPT ![ProxyID] = "Done"]
             /\ UNCHANGED << network, fd, output, msg_, proxyMsg, idx, resp_, 
                             proxyResp, msg, resp_S, req, resp, reqId >>

rcvMsgFromClient == /\ pc[ProxyID] = "rcvMsgFromClient"
                    /\ Assert(((network)[<<ProxyID, REQ_MSG_TYP>>]).enabled, 
                              "Failure of assertion at line 243, column 7.")
                    /\ (Len(((network)[<<ProxyID, REQ_MSG_TYP>>]).queue)) > (0)
                    /\ LET readMsg0 == Head(((network)[<<ProxyID, REQ_MSG_TYP>>]).queue) IN
                         /\ network' = [network EXCEPT ![<<ProxyID, REQ_MSG_TYP>>] = [queue |-> Tail(((network)[<<ProxyID, REQ_MSG_TYP>>]).queue), enabled |-> ((network)[<<ProxyID, REQ_MSG_TYP>>]).enabled]]
                         /\ LET yielded_net3 == readMsg0 IN
                              /\ msg_' = yielded_net3
                              /\ pc' = [pc EXCEPT ![ProxyID] = "proxyMsg_"]
                    /\ UNCHANGED << fd, output, proxyMsg, idx, resp_, 
                                    proxyResp, msg, resp_S, req, resp, reqId >>

proxyMsg_ == /\ pc[ProxyID] = "proxyMsg_"
             /\ Assert((((msg_).to) = (ProxyID)) /\ (((msg_).typ) = (REQ_MSG_TYP)), 
                       "Failure of assertion at line 253, column 7.")
             /\ proxyResp' = [from |-> ProxyID, to |-> (msg_).from, body |-> FAIL, id |-> (msg_).id, typ |-> PROXY_RESP_MSG_TYP]
             /\ idx' = 1
             /\ pc' = [pc EXCEPT ![ProxyID] = "serversLoop"]
             /\ UNCHANGED << network, fd, output, msg_, proxyMsg, resp_, msg, 
                             resp_S, req, resp, reqId >>

serversLoop == /\ pc[ProxyID] = "serversLoop"
               /\ IF (idx) <= (NUM_SERVERS)
                     THEN /\ pc' = [pc EXCEPT ![ProxyID] = "proxySendMsg"]
                     ELSE /\ pc' = [pc EXCEPT ![ProxyID] = "sendMsgToClient"]
               /\ UNCHANGED << network, fd, output, msg_, proxyMsg, idx, resp_, 
                               proxyResp, msg, resp_S, req, resp, reqId >>

proxySendMsg == /\ pc[ProxyID] = "proxySendMsg"
                /\ \/ /\ proxyMsg' = [from |-> ProxyID, to |-> idx, body |-> (msg_).body, id |-> (msg_).id, typ |-> PROXY_REQ_MSG_TYP]
                      /\ LET value7 == proxyMsg' IN
                           /\ ((network)[<<(proxyMsg').to, PROXY_REQ_MSG_TYP>>]).enabled
                           /\ network' = [network EXCEPT ![<<(proxyMsg').to, PROXY_REQ_MSG_TYP>>] = [queue |-> Append(((network)[<<(proxyMsg').to, PROXY_REQ_MSG_TYP>>]).queue, value7), enabled |-> ((network)[<<(proxyMsg').to, PROXY_REQ_MSG_TYP>>]).enabled]]
                           /\ pc' = [pc EXCEPT ![ProxyID] = "proxyRcvMsg"]
                      /\ idx' = idx
                   \/ /\ LET yielded_fd1 == (fd)[idx] IN
                           /\ yielded_fd1
                           /\ idx' = (idx) + (1)
                           /\ pc' = [pc EXCEPT ![ProxyID] = "serversLoop"]
                      /\ UNCHANGED <<network, proxyMsg>>
                /\ UNCHANGED << fd, output, msg_, resp_, proxyResp, msg, 
                                resp_S, req, resp, reqId >>

proxyRcvMsg == /\ pc[ProxyID] = "proxyRcvMsg"
               /\ \/ /\ Assert(((network)[<<ProxyID, PROXY_RESP_MSG_TYP>>]).enabled, 
                               "Failure of assertion at line 280, column 9.")
                     /\ (Len(((network)[<<ProxyID, PROXY_RESP_MSG_TYP>>]).queue)) > (0)
                     /\ LET readMsg == Head(((network)[<<ProxyID, PROXY_RESP_MSG_TYP>>]).queue) IN
                          /\ network' = [network EXCEPT ![<<ProxyID, PROXY_RESP_MSG_TYP>>] = [queue |-> Tail(((network)[<<ProxyID, PROXY_RESP_MSG_TYP>>]).queue), enabled |-> ((network)[<<ProxyID, PROXY_RESP_MSG_TYP>>]).enabled]]
                          /\ LET yielded_net0 == readMsg IN
                               LET tmp == yielded_net0 IN
                                 IF (((tmp).from) # (idx)) \/ (((tmp).id) # ((msg_).id))
                                    THEN /\ pc' = [pc EXCEPT ![ProxyID] = "proxyRcvMsg"]
                                         /\ UNCHANGED proxyResp
                                    ELSE /\ proxyResp' = tmp
                                         /\ Assert((((((proxyResp').to) = (ProxyID)) /\ (((proxyResp').from) = (idx))) /\ (((proxyResp').id) = ((msg_).id))) /\ (((proxyResp').typ) = (PROXY_RESP_MSG_TYP)), 
                                                   "Failure of assertion at line 290, column 17.")
                                         /\ pc' = [pc EXCEPT ![ProxyID] = "sendMsgToClient"]
                     /\ idx' = idx
                  \/ /\ LET yielded_fd00 == (fd)[idx] IN
                          /\ yielded_fd00
                          /\ idx' = (idx) + (1)
                          /\ pc' = [pc EXCEPT ![ProxyID] = "serversLoop"]
                     /\ UNCHANGED <<network, proxyResp>>
               /\ UNCHANGED << fd, output, msg_, proxyMsg, resp_, msg, resp_S, 
                               req, resp, reqId >>

sendMsgToClient == /\ pc[ProxyID] = "sendMsgToClient"
                   /\ resp_' = [from |-> ProxyID, to |-> (msg_).from, body |-> (proxyResp).body, id |-> (msg_).id, typ |-> RESP_MSG_TYP]
                   /\ LET value00 == resp_' IN
                        /\ ((network)[<<(resp_').to, (resp_').typ>>]).enabled
                        /\ network' = [network EXCEPT ![<<(resp_').to, (resp_').typ>>] = [queue |-> Append(((network)[<<(resp_').to, (resp_').typ>>]).queue, value00), enabled |-> ((network)[<<(resp_').to, (resp_').typ>>]).enabled]]
                        /\ pc' = [pc EXCEPT ![ProxyID] = "proxyLoop"]
                   /\ UNCHANGED << fd, output, msg_, proxyMsg, idx, proxyResp, 
                                   msg, resp_S, req, resp, reqId >>

Proxy == proxyLoop \/ rcvMsgFromClient \/ proxyMsg_ \/ serversLoop
            \/ proxySendMsg \/ proxyRcvMsg \/ sendMsgToClient

serverLoop(self) == /\ pc[self] = "serverLoop"
                    /\ IF TRUE
                          THEN /\ IF EXPLORE_FAIL
                                     THEN /\ \/ /\ TRUE
                                                /\ pc' = [pc EXCEPT ![self] = "serverRcvMsg"]
                                                /\ UNCHANGED network
                                             \/ /\ LET value10 == FALSE IN
                                                     /\ network' = [network EXCEPT ![self, PROXY_REQ_MSG_TYP] = [queue |-> ((network)[self, PROXY_REQ_MSG_TYP]).queue, enabled |-> value10]]
                                                     /\ pc' = [pc EXCEPT ![self] = "failLabel"]
                                     ELSE /\ pc' = [pc EXCEPT ![self] = "serverRcvMsg"]
                                          /\ UNCHANGED network
                          ELSE /\ pc' = [pc EXCEPT ![self] = "failLabel"]
                               /\ UNCHANGED network
                    /\ UNCHANGED << fd, output, msg_, proxyMsg, idx, resp_, 
                                    proxyResp, msg, resp_S, req, resp, reqId >>

serverRcvMsg(self) == /\ pc[self] = "serverRcvMsg"
                      /\ Assert(((network)[<<self, PROXY_REQ_MSG_TYP>>]).enabled, 
                                "Failure of assertion at line 334, column 7.")
                      /\ (Len(((network)[<<self, PROXY_REQ_MSG_TYP>>]).queue)) > (0)
                      /\ LET readMsg1 == Head(((network)[<<self, PROXY_REQ_MSG_TYP>>]).queue) IN
                           LET network0 == [network EXCEPT ![<<self, PROXY_REQ_MSG_TYP>>] = [queue |-> Tail(((network)[<<self, PROXY_REQ_MSG_TYP>>]).queue), enabled |-> ((network)[<<self, PROXY_REQ_MSG_TYP>>]).enabled]] IN
                             LET yielded_net10 == readMsg1 IN
                               /\ msg' = [msg EXCEPT ![self] = yielded_net10]
                               /\ Assert(((((msg'[self]).to) = (self)) /\ (((msg'[self]).from) = (ProxyID))) /\ (((msg'[self]).typ) = (PROXY_REQ_MSG_TYP)), 
                                         "Failure of assertion at line 340, column 13.")
                               /\ IF EXPLORE_FAIL
                                     THEN /\ \/ /\ TRUE
                                                /\ network' = network0
                                                /\ pc' = [pc EXCEPT ![self] = "serverSendMsg"]
                                             \/ /\ LET value20 == FALSE IN
                                                     /\ network' = [network0 EXCEPT ![self, PROXY_REQ_MSG_TYP] = [queue |-> ((network0)[self, PROXY_REQ_MSG_TYP]).queue, enabled |-> value20]]
                                                     /\ pc' = [pc EXCEPT ![self] = "failLabel"]
                                     ELSE /\ network' = network0
                                          /\ pc' = [pc EXCEPT ![self] = "serverSendMsg"]
                      /\ UNCHANGED << fd, output, msg_, proxyMsg, idx, resp_, 
                                      proxyResp, resp_S, req, resp, reqId >>

serverSendMsg(self) == /\ pc[self] = "serverSendMsg"
                       /\ resp_S' = [resp_S EXCEPT ![self] = [from |-> self, to |-> (msg[self]).from, body |-> self, id |-> (msg[self]).id, typ |-> PROXY_RESP_MSG_TYP]]
                       /\ LET value30 == resp_S'[self] IN
                            /\ ((network)[<<(resp_S'[self]).to, (resp_S'[self]).typ>>]).enabled
                            /\ LET network1 == [network EXCEPT ![<<(resp_S'[self]).to, (resp_S'[self]).typ>>] = [queue |-> Append(((network)[<<(resp_S'[self]).to, (resp_S'[self]).typ>>]).queue, value30), enabled |-> ((network)[<<(resp_S'[self]).to, (resp_S'[self]).typ>>]).enabled]] IN
                                 IF EXPLORE_FAIL
                                    THEN /\ \/ /\ TRUE
                                               /\ network' = network1
                                               /\ pc' = [pc EXCEPT ![self] = "serverLoop"]
                                            \/ /\ LET value40 == FALSE IN
                                                    /\ network' = [network1 EXCEPT ![self, PROXY_REQ_MSG_TYP] = [queue |-> ((network1)[self, PROXY_REQ_MSG_TYP]).queue, enabled |-> value40]]
                                                    /\ pc' = [pc EXCEPT ![self] = "failLabel"]
                                    ELSE /\ network' = network1
                                         /\ pc' = [pc EXCEPT ![self] = "serverLoop"]
                       /\ UNCHANGED << fd, output, msg_, proxyMsg, idx, resp_, 
                                       proxyResp, msg, req, resp, reqId >>

failLabel(self) == /\ pc[self] = "failLabel"
                   /\ LET value50 == TRUE IN
                        /\ fd' = [fd EXCEPT ![self] = value50]
                        /\ pc' = [pc EXCEPT ![self] = "Done"]
                   /\ UNCHANGED << network, output, msg_, proxyMsg, idx, resp_, 
                                   proxyResp, msg, resp_S, req, resp, reqId >>

Server(self) == serverLoop(self) \/ serverRcvMsg(self)
                   \/ serverSendMsg(self) \/ failLabel(self)

clientLoop(self) == /\ pc[self] = "clientLoop"
                    /\ IF TRUE
                          THEN /\ pc' = [pc EXCEPT ![self] = "clientSendReq"]
                          ELSE /\ pc' = [pc EXCEPT ![self] = "Done"]
                    /\ UNCHANGED << network, fd, output, msg_, proxyMsg, idx, 
                                    resp_, proxyResp, msg, resp_S, req, resp, 
                                    reqId >>

clientSendReq(self) == /\ pc[self] = "clientSendReq"
                       /\ req' = [req EXCEPT ![self] = [from |-> self, to |-> ProxyID, body |-> self, id |-> reqId[self], typ |-> REQ_MSG_TYP]]
                       /\ LET value60 == req'[self] IN
                            /\ ((network)[<<(req'[self]).to, (req'[self]).typ>>]).enabled
                            /\ network' = [network EXCEPT ![<<(req'[self]).to, (req'[self]).typ>>] = [queue |-> Append(((network)[<<(req'[self]).to, (req'[self]).typ>>]).queue, value60), enabled |-> ((network)[<<(req'[self]).to, (req'[self]).typ>>]).enabled]]
                            /\ PrintT(<<"CLIENT START", req'[self]>>)
                            /\ pc' = [pc EXCEPT ![self] = "clientRcvResp"]
                       /\ UNCHANGED << fd, output, msg_, proxyMsg, idx, resp_, 
                                       proxyResp, msg, resp_S, resp, reqId >>

clientRcvResp(self) == /\ pc[self] = "clientRcvResp"
                       /\ Assert(((network)[<<self, RESP_MSG_TYP>>]).enabled, 
                                 "Failure of assertion at line 406, column 7.")
                       /\ (Len(((network)[<<self, RESP_MSG_TYP>>]).queue)) > (0)
                       /\ LET readMsg2 == Head(((network)[<<self, RESP_MSG_TYP>>]).queue) IN
                            /\ network' = [network EXCEPT ![<<self, RESP_MSG_TYP>>] = [queue |-> Tail(((network)[<<self, RESP_MSG_TYP>>]).queue), enabled |-> ((network)[<<self, RESP_MSG_TYP>>]).enabled]]
                            /\ LET yielded_net20 == readMsg2 IN
                                 /\ resp' = [resp EXCEPT ![self] = yielded_net20]
                                 /\ Assert((((((resp'[self]).to) = (self)) /\ (((resp'[self]).id) = (reqId[self]))) /\ (((resp'[self]).from) = (ProxyID))) /\ (((resp'[self]).typ) = (RESP_MSG_TYP)), 
                                           "Failure of assertion at line 412, column 11.")
                                 /\ PrintT(<<"CLIENT RESP", resp'[self]>>)
                                 /\ reqId' = [reqId EXCEPT ![self] = ((reqId[self]) + (1)) % (MSG_ID_BOUND)]
                                 /\ output' = resp'[self]
                                 /\ pc' = [pc EXCEPT ![self] = "clientLoop"]
                       /\ UNCHANGED << fd, msg_, proxyMsg, idx, resp_, 
                                       proxyResp, msg, resp_S, req >>

Client(self) == clientLoop(self) \/ clientSendReq(self)
                   \/ clientRcvResp(self)

(* Allow infinite stuttering to prevent deadlock on termination. *)
Terminating == /\ \A self \in ProcSet: pc[self] = "Done"
               /\ UNCHANGED vars

Next == Proxy
           \/ (\E self \in SERVER_SET: Server(self))
           \/ (\E self \in CLIENT_SET: Client(self))
           \/ Terminating

Spec == /\ Init /\ [][Next]_vars
        /\ WF_vars(Proxy)
        /\ \A self \in SERVER_SET : WF_vars(Server(self))
        /\ \A self \in CLIENT_SET : WF_vars(Client(self))

Termination == <>(\A self \in ProcSet: pc[self] = "Done")

\* END TRANSLATION

\* Invariants

\* Only holds if PerfectFD is used
ProxyOK == (pc[ProxyID] = "sendMsgToClient" /\ proxyResp.body = FAIL) 
                => (\A server \in SERVER_SET : pc[server] = "failLabel" \/ pc[server] = "Done")

\* Properties

ReceiveResp(client) == pc[client] = "clientSendReq" ~> pc[client] = "clientRcvResp"
ClientsOK == \A client \in CLIENT_SET : ReceiveResp(client)

=============================================================================
\* Modification History
\* Last modified Fri Aug 20 00:15:25 PDT 2021 by shayan
\* Created Wed Jun 30 19:19:46 PDT 2021 by shayan