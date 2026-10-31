# SwarmSense RGB Mesh Digital Twin

A six-node ESP32 mesh demonstration with a React digital twin and a Node.js event backend.

## What runs now

The application starts in simulation mode and changes automatically to physical-hardware mode when ESP32 UDP telemetry arrives. The interface includes a switchable 2D network and 3D constellation twin. The 3D geometry is explicitly synthetic until positioning hardware is connected. A contact-plan timeline shows CGR availability, latency, capacity, confidence and stored bundles.

The backend models what the identical ESP32 firmware calculates independently; the browser is only a digital-twin observer:

- EWMA/PDR-style link costs;
- composite neighbour quality using RSSI EWMA, delivery ratio, acknowledgement RTT, queue pressure and instability;
- distributed two-neighbour consensus from temporary discovery measurements;
- topology hysteresis, a minimum hold time and heartbeat-triggered six-node ring repair;
- automatic max-consensus gateway election with gateway leases and challenger margins;
- per-node CBBA bundle construction, winner-vector consensus and task leases;
- confidence-, deadline-, route- and resource-aware bid terms with versioned ownership epochs;
- time/distance/color target correlation to merge duplicate detections;
- earliest-arrival Contact Graph Routing;
- an edge-disjoint backup contact route;
- DTN bundle custody events;
- a bounded, priority-ordered persistent DTN result queue;
- contact blackout, persistent storage and later forwarding;
- coordinated versus greedy resource costs.

## Start

Development:

    npm run dev

Open http://localhost:5173

Single-server production mode:

    npm run build
    npm start

Open http://localhost:4100

You can also double-click START_ORBIT.cmd.

## Hardware bridge

The ground centre is this laptop. `START_ORBIT.cmd` starts a UDP listener on port `4210`; no ESP32 remains connected by USB during the demonstration. All six nodes join hotspot `FAB`, elect their gateway independently, and route telemetry through the mesh. Only the elected gateway sends the collected events to the laptop. The laptop visualises decisions but never selects neighbours, winners, routes, or the gateway.

Before the first run, connect one board at a time and assign unique IDs:

    FLASH_NODE.cmd 0 COM3
    FLASH_NODE.cmd 1 COM3

Continue through ID `5`, changing the COM port where necessary. Then turn on the `FAB` hotspot, battery-power all boards, double-click `START_ORBIT.cmd`, and open http://localhost:4100.

The authenticated endpoint used internally by the serial bridge is:

    POST http://GROUND_PC_IP:4100/api/hardware/event
    Content-Type: application/json
    x-hardware-token: orbit-demo-local

Example payload:

    {
      "type": "PACKET_FORWARDED",
      "message": "N-02 to N-03",
      "node": 1,
      "from": 1,
      "to": 2,
      "taskId": "RGB-0042",
      "led": "#2DE8CD",
      "distanceCm": 31.4,
      "battery": 81,
      "buffer": 70
    }

If physical packets stop, the dashboard marks individual nodes offline rather than inventing live values. Simulation remains available as a separate demonstration mode.

## API

- GET /api/state
- GET /api/health
- GET /api/history
- POST /api/task
- POST /api/gateway/reelect
- POST /api/cbba/recovery
- POST /api/failure
- POST /api/reset
- POST /api/hardware/event

Events and completed scenario summaries are stored as JSON Lines under `data/`, allowing evidence from a demo run to survive a backend restart.

## Tests

    npm test

## Startup troubleshooting

START_ORBIT.cmd calls Start-Orbit.ps1, keeps the backend in the foreground, and writes all startup output to orbit-backend.log. Keep the backend window open while using the dashboard.


## Decentralized control model

All six nodes run the same logic with equal authority. Each node temporarily observes discovery candidates, retains only two active peers after convergence, participates in task allocation, routes or stores bundles, and calculates the same gateway winner from gossiped advertisements. The laptop is a passive data sink and dashboard, not a topology or task controller.

## Phase 2 firmware

The `firmware` directory contains one PlatformIO project for all six ESP32 boards. It includes HC-SR04 sampling, detection cooldown, encrypted ESP-NOW unicast, automatic connected two-neighbour topology, local CBBA bundles, neighbour-to-neighbour winner-vector consensus, relative expiring task leases, owner-failure reassignment and persistent result storage. Provision only the persistent node ID (`0` through `5`); every board runs the same binary and has equal authority.
