# ESP32 message and algorithm plan

## Radio behavior

All six ESP32s are independent peers. ESP-NOW is half-duplex, so simultaneous behavior is implemented with asynchronous callbacks, FreeRTOS queues, acknowledgements and random backoff rather than literal simultaneous radio transmission.

Deadline and lease fields are transmitted as remaining durations, not absolute ESP32 `millis()` values. Every receiver converts them to its own local clock. This avoids requiring clock synchronisation between boards.

## Packet header

Recommended fields:

- version
- messageType
- sourceId
- destinationId
- previousHop
- nextHop
- sequenceNumber
- topologyEpoch
- taskId
- hopCount
- hopLimit
- payloadLength
- CRC

RGB payload:

- red: uint8
- green: uint8
- blue: uint8
- leaseMilliseconds: uint16

## Message types

HELLO, LINK_REPORT, TOPOLOGY_EPOCH, HEARTBEAT, GATEWAY_CANDIDATE, TASK_ANNOUNCE, CBBA_CLAIM, TASK_COMPLETE, LEASE_RELEASE, RGB_RESULT, FORWARD, ACK, ROUTE_ERROR and GROUND_DELIVERED.

## Improved algorithms

1. Neighbor quality: RSSI EWMA, active probe delivery ratio, acknowledgement RTT, queue pressure and signal-instability penalty.
2. Topology: every peer temporarily ranks discovery candidates, rejects stale link-report epochs and independently evaluates the same deterministic degree-2 cycle. Hold-down and improvement margins prevent flapping; heartbeat loss bypasses the hold-down for immediate self-healing. After convergence it retains two active routing peers.
3. Gateway: every peer runs the same max-consensus score with ground RSSI, battery, buffer, queue headroom and stability. A gateway lease and challenger margin prevent unnecessary changes. Elections are periodic and triggered by gateway heartbeat loss; there is no permanent head.
4. Ownership: CBBA. Every node builds a local task bundle and exchanges winning-agent and winning-bid vectors only with its two neighbours. Higher bid wins; equal bids use the lower node ID.
5. Duplicate control: task ID, target correlation, topology epoch, message sequence number, lease epoch and expiring ownership.
6. Routing: lightweight Contact Graph Routing selects the earliest-arrival healthy path over the accepted tabletop contact ring; the backend models explicit future contact windows.
7. Backup: exclude the primary contact edges and run CGR again for an independent contact path.
8. Reliability: DTN bundles use hop-by-hop custody events, sequence numbers and bounded retransmission.
9. Failure: one-second heartbeat and failure after three misses.
10. Recovery: remove the failed contact and recompute the earliest-arrival contact path locally.
11. Partition: retain up to four RGB results in a priority-ordered LittleFS custody queue and forward them after connectivity returns.
12. Equal authority: every board runs the same firmware and can originate RGB tasks, bid, relay, store bundles, detect faults and become gateway.
13. Local self-healing: after three missed heartbeats, advertise the failed edge, keep the surviving peer, converge on a replacement topology epoch, confirm the replacement, then remove stale peer state.
14. Demo transport security: use a shared ESP-NOW PMK and encrypted unicast LMK; discovery broadcasts remain readable so unknown peers can join.
15. Persistence: write the completed RGB result to LittleFS before delivery, report `bundleStored`, and retry it after a reset or lost ground link. Clear it only after a `GROUND_ACK` carrying the matching task ID returns through the mesh.

## Laptop serial bridge

The backend scans USB serial ports every five seconds at 115200 baud. On connection it sends `GROUND 1` to the attached node. Firmware emits one JSON object per line; the bridge adds the serial-port identity and posts it to `/api/hardware/event` with the local hardware token. The REST endpoint is not used by ESP-NOW peers and never participates in CBBA.

For the intended demo, connect one ESP32 to the laptop by USB. If several are connected, all may advertise a ground contact, but the shared weighted gateway score and deterministic node-ID tie-break still elect one gateway.

## Suggested FreeRTOS tasks

- DiscoveryTask
- LinkEstimatorTask
- TopologyTask
- GatewayElectionTask
- CbbaConsensusTask
- RouterTask
- RgbLedTask
- DisplayButtonTask
- GroundBridgeTask
- TelemetryTask

ESP-NOW receive and send callbacks should only validate the minimum header and enqueue messages. Routing, display, LED and flash operations should occur in their own tasks.

## Digital-twin events

Firmware should send the same event names used by the backend:

- NODE_ONLINE
- LINK_UPDATED
- GATEWAY_CHANGED
- TARGET_DETECTED
- CBBA_BIDS
- CBBA_CONSENSUS_ROUND
- CBBA_CONVERGED
- TASK_LEASED
- TASK_REASSIGNED
- RGB_APPLIED
- ROUTE_SELECTED
- PACKET_FORWARDED
- HOP_ACK
- LINK_FAILED
- LINK_RESTORED
- STORE_FORWARD
- GROUND_DELIVERY

This lets the React interface move from simulation to hardware without changing its visualization model.

## Ownership and conflict resolution

Every task has one canonical task ID. Each node keeps `winner[taskId]`, `winningBid[taskId]`, bundle position and `leaseUntil`. CBBA claims propagate through the two-neighbour ring. A higher bid replaces a lower bid; an exact tie uses the lower node ID. A node that loses an item removes that item and every dependent item after it from its bundle, then rebuilds. Execution begins only after winner vectors remain unchanged for the consensus-settle interval and the local node still owns a valid lease.

The firmware uses one active task per configured zone and a detection cooldown. If simultaneous nodes create IDs for the same shared zone, the lower ID becomes canonical. This is appropriate for the tabletop prototype. Real ISR systems require geolocation and track-to-track correlation to decide whether observations represent the same physical target.

## Owner failure and reassignment

Peers expect heartbeats before the timeout. When the owner disappears, its lease is allowed to expire; no peer executes using the expired ownership record. The task returns to the available set, remaining nodes rebuild their CBBA bundles and exchange winner vectors, and the new winner receives a fresh lease with a newer epoch. A rejoining node first accepts the latest task, completion and winner vectors before it can bid again.
