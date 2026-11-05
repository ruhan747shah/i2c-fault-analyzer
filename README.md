
# I²C Protocol Analyzer and Fault Capture

A simulation-verified, synthesizable SystemVerilog I²C protocol analyzer with timestamped event logging and fault-triggered circular capture.

Designed as an FPGA hardware-debugging project to investigate I²C sensor communication failures.

## Features

- Passive monitoring of SDA and SCL
- START, STOP, and repeated START detection
- 7-bit device address and read/write decoding
- Data-byte decoding
- ACK/NACK classification
- Address-NACK fault detection
- Normal read-completion NACK recognition
- 32-bit event timestamps
- 16-entry circular event buffer
- Eight pre-trigger events, one trigger, seven post-trigger events
- Clock stretching and reset recovery tests
- Automated simulation verification using Python
- Generic logic synthesis using Yosys

## Architecture

```text
Simulated I²C Controller + Sensor
              |
          SDA / SCL
              |
              v
    Input Synchronization
              |
              v
     Transaction Decoder
              |
              v
      Timestamped Events
              |
              v
    Circular Fault Capture
              |
              v
       Readback Interface
```

The analyzer never drives SDA or SCL.

### Transaction Decoder

`rtl/i2c_transaction_decoder.sv`

Uses a finite-state machine to decode I²C bus activity.

States:

- IDLE
- ADDR_BITS
- ADDR_ACK
- DATA_BITS
- DATA_ACK
- WAIT_END

The decoder samples SDA on synchronized SCL rising edges.

### Event Logger

`rtl/i2c_event_logger.sv`

Converts decoded events into structured records containing:

- Event type: 4 bits
- Event data: 8 bits
- Timestamp: 32 bits

At a 50 MHz system clock, each timestamp tick represents 20 ns.

### Fault Capture

`rtl/i2c_fault_capture.sv`

Maintains a rolling history of the eight most recent events.

When an address NACK occurs:

1. Preserve eight preceding events.
2. Store the address-NACK trigger.
3. Capture seven subsequent events.
4. Freeze the 16-entry buffer.
5. Allow indexed readback.

If fewer than eight earlier events exist, fewer entries are retained.

A read-completion NACK does not trigger fault capture.

The buffer requires reset before another capture.

## Supported Protocol Behavior

The current implementation supports standard 7-bit I²C transfers, including:

- Addressed read and write operations
- Multiple data bytes
- Repeated START conditions
- ACK and NACK responses
- Clock stretching, where SCL remains low longer
- Reset during a transaction

Address NACKs are classified separately from NACKs occurring after read data.

## Simulation Verification

The RTL was tested using Icarus Verilog.

Run all tests:

```bash
python3 scripts/run_tests.py
```

Test coverage:

| Test | Behavior |
|---|---|
| START/STOP | Detect bus start and stop conditions |
| Address decoder | Decode 7-bit address and R/W |
| ACK/NACK | Verify responding and missing devices |
| Transaction decoder | Decode data and repeated START |
| Event logger | Verify event order and timestamps |
| Circular capture | Verify pre/post-trigger events |
| Edge cases | Verify clock stretching and reset |

The regression script generates a simulation report in
`reports/simulation_report.txt`.

### Waveforms

Simulations generate VCD files inside `sim/`.

Example:

```bash
gtkwave sim/i2c_fault_capture.vcd
```

Important signals include:

- `sda`
- `scl`
- `event_valid`
- `event_type`
- `event_timestamp`
- `fault_triggered`
- `capture_done`
- `capture_count`

## Yosys Synthesis Results

The integrated RTL was synthesized with Yosys.

Run:

```bash
bash scripts/run_synthesis.sh
```

Observed generic synthesis results:

| Metric | Result |
|---|---:|
| Total cells | 2,678 |
| Flip-flop cells | 849 |
| Remaining memory bits | 0 |
| RTL modules in hierarchy | 4 |

These are generic Yosys synthesis statistics, not results from a specific FPGA architecture.

The event buffer was mapped into logic and flip-flops rather than FPGA block RAM.

No hardware implementation or timing closure is claimed.

## Sampling Assumptions

- The monitor uses a 50 MHz system clock in the supplied tests.
- SDA and SCL are synchronized before decoding.
- I²C transitions must remain stable long enough to be sampled.
- The design assumes a single controller and conventional I²C timing.
- Clock stretching is observed through the synchronized SCL input.
- The simulation uses idealized digital open-drain signals.

## Limitations

- Simulation and generic logic synthesis only
- No physical FPGA validation yet
- No 10-bit address support
- No multi-controller arbitration detection
- No analog signal integrity measurements
- No programmable digital glitch filter
- No automatic buffer rearming
- No FPGA-specific timing analysis
- NACK classification is based on transaction phase; normal read NACKs are recognized but the design does not infer application-level intent

## Tools

- SystemVerilog
- Icarus Verilog
- GTKWave
- Python 3
- Yosys
- Git

## Future Improvements

- Hardware demonstration on an FPGA board
- FPGA block-RAM-based event storage
- Configurable fault triggers
- Programmable pre/post-trigger depth
- UART streaming of captured events
- Bus timing and glitch detection
- 10-bit address support

## Verification Status

**Simulation:** Individual functional and fault-capture tests passed in Icarus Verilog.

**Synthesis:** Integrated RTL successfully synthesized using Yosys.

**Hardware:** Not tested on a physical FPGA.
## Simulation Waveforms

### Full I²C Simulation

![Full I2C Simulation](examples/waveforms/full_simulation.png)

Shows simulated I²C transactions, decoded events,
timestamps, and fault-capture status.

### Address-NACK Fault Trigger

![Address NACK Trigger](examples/waveforms/address_nack_trigger.png)

Shows an address NACK triggering the capture buffer.
The buffer preserves eight preceding events and
records seven subsequent events before freezing.

## Verification Results

- **Simulation:** 6/6 automated test suites passed
- **Fault capture:** 16 timestamped events verified
- **Yosys synthesis:** 2,678 generic logic cells
- **Hardware:** Not yet tested on a physical FPGA

All results are from simulation or generic synthesis,
not physical hardware measurements.

## Author

Ruhan Shah  
Electrical Engineering — University of Waterloo

GitHub: https://github.com/ruhan747shah

