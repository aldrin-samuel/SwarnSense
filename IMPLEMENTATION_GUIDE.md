# SwarmSense implementation and domain guide

## 1. Problem being solved

A group of CubeSats, drones, or remote ESP32 sensor nodes may see the same event at nearly the same time. If every node independently captures it, the network creates duplicate images or measurements, consumes battery, fills flash storage, and congests the route to the ground station.

SwarmSense moves the immediate decision loop onto the nodes. Nearby peers discover one another, form a resilient two-neighbour network, announce a target as a task, compare bids, grant short ownership leases to the best sensors, and route only useful products through whichever node currently has the best ground link. The ground station is a passive data sink and digital-twin observer; it does not choose neighbours, routes, task owners, or the gateway.

## 2. What is implemented in the browser prototype

The local dashboard is a deterministic idea-evaluation simulator, not a radio or orbital simulator. It models six identical, equal-authority nodes:

1. Every node temporarily observes discovery replies and derives RSSI/PDR link costs.
2. Every node applies the same deterministic degree-2 topology rule and retains only two active peers.
3. Every node independently evaluates the same gateway score; identical inputs and a node-ID tie break produce consensus without a permanent head.
4. CBBA gives every node its own task bundle and winner vectors; neighbour consensus selects one RGB task owner while a lease suppresses duplicate execution.
5. Contact Graph Routing selects the earliest-arrival contact path.
6. DTN custody and store-and-forward retain a bundle when no route exists.
7. Three missed heartbeats mark a peer link failed and trigger automatic neighbour replacement.
8. Periodic elections automatically reconsider the gateway; the dashboard button only triggers an immediate demonstration round.
9. The dashboard exposes node neighbours, active hops, resource costs, election events, and coordinated-versus-greedy behavior.

The Node backend executes one copy of this logic to simulate the results produced by identical firmware. It is not the proposed system's controller. In hardware, the same algorithms run on every ESP32.

## 3. Algorithms and where each is used

| Layer | Algorithm | Purpose | Current implementation |
|---|---|---|---|
| Link measurement | Smoothed RSSI + PDR + ACK/queue penalty | Rank responsive, reliable candidates | `buildLinkTable()` simulation model |
| Topology | Deterministic distributed degree-2 consensus | Give every node two feasible peers while preserving one connected ring | `distributedNeighbourConsensus()` |
| Gateway | Weighted max-consensus + node-ID tie break | Select a temporary ground relay without a controller | `electGateway()` |
| Task allocation | Consensus-Based Bundle Algorithm (CBBA) | Select owners for one or more targets without a central allocator | `server/cbba.js` |
| Duplicate prevention | Task ID + expiring ownership lease | Make losing bidders stand down | coordinated task workflow |
| Primary routing | Contact Graph Routing | Select earliest-arrival scheduled contacts | `contactGraphRoute()` |
| Backup routing | CGR excluding primary edges | Find an independent alternative contact path | `dualContactRoute()` |
| Failure detection | Three missed heartbeats | Declare an active peer unavailable | hardware protocol / failure control |
| Recovery | New topology epoch + peer replacement | Restore two neighbours without ground commands | failure endpoint simulation |
| Disconnected operation | DTN custody and store-and-forward | Keep bundles in flash until contact returns | bundle queue simulation |

### 3.1 Link cost

On real ESP32 hardware, each receive callback can read RSSI from the receive metadata. Use an exponentially weighted moving average:

RSSI_ema(t) = alpha × RSSI_sample(t) + (1 − alpha) × RSSI_ema(t−1)

A practical alpha is 0.2 to 0.3. Packet delivery ratio is measured over a recent acknowledgement window:

PDR = acknowledged packets / transmitted packets

The prototype combines normalised terms:

LinkCost = 0.62 × RSSI_penalty + 0.38 × (1 − PDR)

Lower cost is better. For hardware, add queue delay or estimated transmission energy if needed. Do not rank links from raw RSSI alone: reflections, orientation, interference, and antenna nulls can make a single sample misleading.

### 3.2 Why a degree-2 ring instead of only “pick the two strongest neighbours”

If every node independently keeps its two strongest peers, the result can contain disconnected clusters or asymmetric choices. The implemented solution gossips a small topology epoch during discovery and every equal-authority node independently computes the same lowest-cost feasible cycle. Candidate observations are temporary; after convergence each ESP32 retains only its two active peers and compact epoch state. A cycle guarantees:

- every node has exactly two neighbours;
- there are two directions around the ring while all links are healthy;
- one link failure does not partition the six-node network;
- routing and recovery remain easy to explain and test.

For six nodes, exact enumeration is tiny: fixing one start node leaves 5! = 120 orders. For a large constellation, factorial search is unsuitable. Replace it with a distributed ring-maintenance method, a nearest-neighbour plus 2-opt heuristic, or a degree-constrained topology optimiser.

### 3.3 Why MST is not the final topology

A minimum spanning tree is useful for connecting all nodes with N−1 low-cost links. It does not guarantee degree two, can create high-degree hubs, and has no alternate path after a single tree edge fails. It can be used as an initial connectivity backbone, but it conflicts with this prototype’s exact two-neighbour and one-link-fault-tolerance requirements. The degree-2 ring is therefore a better base topology.

### 3.4 Contact Graph Routing and backup contacts

Routing is performed after neighbour formation. Contact Graph Routing evaluates directed contacts with an availability window, latency, capacity, and confidence, then chooses the earliest-arrival path to the temporary gateway. If no contact path exists, the node retains the RGB bundle in flash under DTN custody.

For the demonstration, a backup route is calculated by excluding the primary path edges and running CGR again. Dijkstra remains only a useful comparison for always-connected terrestrial graphs; CGR + DTN is the selected solution for intermittently connected orbital and aerial meshes.

### 3.5 Temporary gateway election

Every node can calculate the same candidate scores after exchanging status beacons:

GatewayScore = 0.65 × GroundLinkQuality + 0.20 × Battery + 0.15 × FreeFlash

The highest score wins; equal scores use the lower node ID as a deterministic tie break. Every node receives the same signed candidate advertisements and calculates the result locally. Elections run periodically and after gateway heartbeat loss. The dashboard button only triggers an immediate demonstration round.

For hardware, add hysteresis so the gateway changes only when a candidate is meaningfully better, for example by 5 score points, or when the current gateway becomes unavailable. This prevents route flapping.

### 3.6 CBBA task allocation

Any ESP32 can originate an ultrasonic target task. Eligible peers calculate a bid from target distance, remaining battery, free buffer, route/contact quality, availability, workload, energy cost and deadline feasibility. Every peer builds its own ordered bundle, stores local winning-agent and winning-bid vectors, and exchanges those vectors only through its two active neighbours. Conflicts use the higher bid and then lower node ID. Losing an early bundle item releases that item and its dependent suffix before rebuilding.

The winner receives a short task lease. All peers cache the task ID, owner, topology epoch, and lease expiry. Only the owner applies the RGB value and produces the result bundle. If its lease expires without completion, peers re-run allocation. This models autonomous target ownership and prevents adjacent sensors from producing duplicate captures.

## 4. ESP32 implementation mapping

### 4.1 Radio

Use ESP-NOW for the five- or six-board prototype. It supports direct low-latency ESP32 communication without an access point. Put all boards on one fixed Wi-Fi channel. Use unicast for normal neighbour traffic and a limited broadcast only for initial discovery.

Each board should store only its two active ring peers after topology convergence, even though it may temporarily observe more candidates during discovery.

### 4.2 Suggested firmware tasks

- Discovery task: emits HELLO beacons and updates RSSI/PDR estimates.
- Topology task: exchanges link summaries, computes the ring, and adds/removes two ESP-NOW peers.
- Heartbeat task: sends liveness messages and marks a link failed after a configurable number of misses.
- Sensor task: samples the HC-SR04, applies a three-reading trigger and detection cooldown, and announces a shared-zone target.
- CBBA task: builds the local bundle, exchanges winner vectors, releases conflicts, grants leases after consensus and controls execution.
- Router task: runs Contact Graph Routing, forwards available contacts, and hands unavailable bundles to flash custody.
- Storage task: persists data and metadata to flash, applies priority and expiry, and supports store-and-forward.
- Ground-link task: reports ground RSSI and participates in gateway elections.
- Safety supervisor: enforces minimum battery, storage reserve, sensor duty-cycle, and watchdog rules.

FreeRTOS queues should separate the ESP-NOW callback from parsing, routing, flash writes, and task allocation. Keep receive callbacks short.

### 4.3 Message types

A compact binary header can contain:

- protocol version;
- message type;
- source and final destination IDs;
- sequence number;
- task ID;
- epoch;
- hop count and hop limit;
- payload length;
- CRC or authenticated integrity result.

Useful message types are HELLO, LINK_REPORT, TOPOLOGY_EPOCH, HEARTBEAT, TARGET_ANNOUNCE, BID, AWARD, LEASE_RENEW, LEASE_RELEASE, DATA_META, DATA_CHUNK, ACK, GATEWAY_CANDIDATE, and ROUTE_ERROR.

Add a duplicate cache keyed by source plus sequence number. Add a hop limit to prevent forwarding loops.

### 4.4 Example timing for a table-top demonstration

- HELLO beacon: every 500 ms.
- RSSI EWMA alpha: 0.25.
- PDR window: last 20 transmissions.
- Heartbeat: every 1 second.
- Failure declaration: 3 missed heartbeats.
- Topology recomputation: on failure or after several stable link samples, not on every packet.
- Gateway election: every 5 seconds or on ground-link loss.
- Task bid window: 300 to 800 ms.
- Task lease: 5 seconds in the demo; mission-specific in production.
- Route entry expiry: 10 to 30 seconds.

These are prototype starting values, not flight-certified parameters.

### 4.5 Ground connection

The current head can use a second interface to reach the ground laptop:

- one ESP32 connected by USB serial;
- Wi-Fi station mode to a laptop hotspot while ESP-NOW remains on the same channel;
- LoRa or another modem attached to the elected gateway.

For the cleanest hackathon demo, keep the ground laptop passive. It receives telemetry and data but does not choose neighbours, routes, or sensing owners.

## 5. End-to-end event sequence

1. Six identical nodes boot with equal authority and exchange authenticated HELLO messages.
2. Each node smooths RSSI, measures delivery/ACK behavior, and temporarily ranks candidates.
3. Nodes gossip a topology epoch, independently reach the same degree-2 result, and retain two active peers.
4. Nodes advertise battery, free flash, workload, and ground-link quality.
5. Every peer calculates the same temporary gateway winner.
6. Any node publishes an RGB task.
7. Eligible nodes calculate bids; one deterministic winner receives the lease and the others stand down.
8. The owner applies the RGB value and creates a DTN bundle.
9. CGR selects the earliest-arrival contact path; each hop accepts custody and acknowledges reception.
10. The temporary gateway forwards the bundle to the passive ground centre.
11. After three missed heartbeats, the failed edge is advertised and a new topology epoch replaces the missing neighbour.
12. If no route exists, the current custodian stores the bundle in flash until a contact returns.
13. Periodic or failure-triggered max-consensus elections can move the gateway to any healthy node.

## 6. Self-healing and consistency rules

A robust implementation needs more than rerouting:

- Use topology epochs so old neighbour information cannot overwrite a newer ring.
- Use deterministic tie breaks so independent nodes reach the same result.
- Require several stable samples before changing a neighbour.
- Add gateway hysteresis and a minimum tenure.
- Make leases expire automatically if an owner fails.
- Re-auction when the winning node misses an execution heartbeat.
- Persist unfinished high-priority tasks across reboot.
- Use sequence numbers, acknowledgements, bounded retries, and hop limits.
- Detect network partitions; do not claim self-healing if no alternate path exists.
- Reconcile task ledgers when partitions merge.

## 7. Security

ESP-NOW supports CCMP protection for unicast frames with a Primary Master Key and per-peer Local Master Keys. Do not leave the default PMK in a judged security design. Provision unique keys, reject unknown node IDs, authenticate topology and task-control messages, and prevent replay with epochs plus sequence numbers.

Broadcast ESP-NOW encryption is not supported in the same way as encrypted unicast, so discovery broadcasts should carry no sensitive command or should add application-layer authentication. A flight system should use mission-approved cryptography, secure boot, signed firmware, protected keys, and a standard such as Bundle Protocol Security where applicable.

## 8. Store-and-forward and the flight-system bridge

The ESP32 prototype can persist a small product or metadata record in LittleFS or an SD card. The queue should be ordered by priority and expiry, with reserved space for critical telemetry.

A flight implementation should not treat ordinary Wi-Fi routing as a complete space protocol. Space links are intermittent and scheduled. NASA’s Delay/Disruption Tolerant Networking uses store-and-forward delivery, and Bundle Protocol Version 7 provides endpoint IDs, bundle lifetime, hop count, fragmentation support, and status reporting. SwarmSense’s flash queue and route-recovery idea maps naturally to DTN, but the current browser does not implement BPv7.

## 9. Domain relevance

### NASA

NASA’s four-CubeSat Starling mission is the closest demonstrated analogue. Starling has tested mobile ad-hoc crosslinks, autonomous coordination, reactive operations, and Distributed Spacecraft Autonomy. NASA reports that the spacecraft shared state and autonomously selected observations to optimise data collection without direct ground control. This validates the problem direction, not the exact algorithms or performance figures used in this prototype.

### ISRO

ISRO’s SpaDeX is not a sensor-swarm mission, but it is relevant evidence for autonomous inter-satellite cooperation. ISRO describes an inter-satellite communication link with onboard intelligence so each spacecraft knows the state of the other, and it demonstrated autonomous rendezvous and docking. The overlap is state sharing and onboard autonomy; SpaDeX does not establish this project’s task-auction or sensing architecture.

### Kepler Aerospace

Kepler Aerospace describes an end-to-end stack spanning satellite hardware, ground-station infrastructure, mission operations, automation, swarming-enabled collection, and multi-sensor intelligence. That makes this project strategically aligned with three parts of its stated domain:

- autonomous swarming satellites;
- real-time multi-sensor collection and intelligence;
- resilient routing into a distributed ground-station network.

The strongest hackathon framing is therefore not “we invented satellite swarms.” It is: “we built an edge coordination layer that decides which sensor should observe, prevents redundant capture, and routes the useful product through a changing gateway before Kepler’s ground and intelligence stack takes over.”

## 10. What the prototype does not claim

- Browser RSSI values are simulated, not measured.
- The under-two-second latency is an illustrative animation target, not a measured radio or flight result.
- Battery and flash percentages are deterministic scenario units, not hardware power measurements.
- The dashboard does not model orbital mechanics, line of sight, antenna patterns, radiation, attitude control, thermal limits, or regulatory spectrum constraints.
- ESP32 and ESP-NOW are table-top analogues, not flight-qualified satellite avionics or crosslinks.
- The exact cycle solver is suitable for six nodes, not a hundred-node swarm.
- A single ring tolerates one link failure but has limited bandwidth and can partition after a second independent failure.
- The current UI represents store-and-forward behavior but does not implement BPv7.
- A production mission needs formal verification, fault containment, cybersecurity review, hardware-in-the-loop testing, and mission-specific safety rules.

## 11. Corrected demonstration metrics

The coordinated path consumes 15 battery units and 15 flash units. The greedy path consumes 54 battery units and 62 flash units.

- Battery reduction: (54 − 15) / 54 = 72.2%, displayed as 72%.
- Flash reduction: (62 − 15) / 62 = 75.8%, displayed as 76%.
- Greedy redundancy: four duplicate captures out of five total = 80%.
- Coordinated output: one leased RGB result bundle, with zero same-task duplicates.

These numbers are internally consistent scenario accounting and remain explicitly labelled as illustrative prototype metrics.

## 12. Recommended hardware validation tests

1. Discovery: power boards in random order and verify automatic MAC discovery.
2. Topology: move boards and verify the same ring epoch is calculated on all six.
3. Degree rule: confirm every node stores exactly two active neighbours.
4. Task conflict: inject the same target at two nodes and verify one lease owner.
5. Duplicate control: verify exactly one node receives the RGB lease and the other five stand down.
6. Low battery: set a node below the safety threshold and verify it cannot win.
7. Low flash: fill one node and verify its bid falls or becomes ineligible.
8. Gateway mobility: attenuate the current head’s ground signal and verify a new election.
9. Link failure: power off one intermediate node or block one peer and verify rerouting.
10. Partition: break two links and verify data is stored instead of falsely reported delivered.
11. Recovery: restore contact and verify queued data drains without duplication.
12. Replay/security: resend an old award and verify epoch/sequence rejection.
13. Reboot: restart a winner and verify lease timeout plus re-auction.
14. Load: inject several tasks and measure allocation latency, packet loss, queue growth, and energy.

## 13. Judge-facing explanation

“Six identical, equal-authority nodes automatically choose two reliable peers and agree on a temporary gateway without a permanent controller. Any node can publish an RGB task; a resource-aware auction grants one short ownership lease so the others do not waste battery or flash on duplicates. Contact Graph Routing and DTN carry the bundle toward ground, while heartbeat failure automatically triggers neighbour replacement and a new topology epoch.”

## 14. Authoritative references

- NASA, What is Starling?: https://www.nasa.gov/smallspacecraft/what-is-starling/
- NASA, Distributed Spacecraft Autonomy: https://www.nasa.gov/game-changing-development-projects/distributed-spacecraft-autonomy-dsa/
- NASA, Delay/Disruption Tolerant Networking: https://www.nasa.gov/communicating-with-missions/delay-disruption-tolerant-networking/
- IETF RFC 9171, Bundle Protocol Version 7: https://www.rfc-editor.org/rfc/rfc9171.html
- Espressif, ESP-NOW API and security: https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-reference/network/esp_now.html
- Espressif, Arduino ESP-NOW overview: https://docs.espressif.com/projects/arduino-esp32/en/latest/api/espnow.html
- ISRO, SpaDeX mission: https://www.isro.gov.in/ISRO_EN/mission_SpaDeX.html
- Kepler Aerospace, company and systems overview: https://kepleraero.com/
- Kepler Aerospace, about: https://kepleraero.com/about.html

## 15. Local files

- `src/App.jsx`: React dashboard, controls, peer views, metrics, and event trace.
- `src/ThreeTwin.jsx`: 3D constellation digital twin.
- `server/algorithms.js`: neighbour consensus, gateway election, CGR, and DTN helpers.
- `server/cbba.js`: feasibility-filtered utility, per-node bundle construction, neighbour consensus and leases.
- `firmware/`: identical ESP32 firmware implementing HC-SR04 detection, ESP-NOW and CBBA locally.
- `server/index.js`: simulation state, automatic elections, self-healing, APIs, and hardware event bridge.
- `HARDWARE_PROTOCOL.md`: ESP32 packet and firmware-task mapping.
