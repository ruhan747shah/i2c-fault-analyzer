
`timescale 1ns/1ps

module tb_i2c_address_decoder;

    // 50 MHz system clock
    logic clk = 0;
    always #10 clk = ~clk;

    logic rst_n = 0;

    // Open-drain I2C bus
    tri1 sda;
    tri1 scl;

    logic controller_sda_low = 0;
    logic controller_scl_low = 0;
    logic sensor_sda_low = 0;

    assign sda = controller_sda_low ? 1'b0 : 1'bz;
    assign sda = sensor_sda_low ? 1'b0 : 1'bz;
    assign scl = controller_scl_low ? 1'b0 : 1'bz;

    // Decoder outputs
    logic [6:0] address;
    logic rw;
    logic address_valid;
    logic ack_valid;
    logic address_acked;
    logic address_nack;

    // Verification counters
    integer address_events = 0;
    integer ack_events = 0;
    integer nack_events = 0;

    // Expected sensor response
    logic expected_ack = 1;

    i2c_address_decoder dut (
        .clk(clk),
        .rst_n(rst_n),
        .sda(sda),
        .scl(scl),
        .address(address),
        .rw(rw),
        .address_valid(address_valid),
        .ack_valid(ack_valid),
        .address_acked(address_acked),
        .address_nack(address_nack)
    );

    // Self-checking event monitor
    always @(posedge clk) begin
        #1;

        if (rst_n) begin

            if (address_valid) begin
                address_events = address_events + 1;

                $display(
                    "[%0t] ADDRESS: 0x%02h R/W=%0b",
                    $time, address, rw
                );

                if (address !== 7'h48 || rw !== 1'b0)
                    $fatal(1, "FAIL: Incorrect address");
            end

            if (ack_valid) begin
                ack_events = ack_events + 1;

                if (address_acked !== expected_ack)
                    $fatal(1, "FAIL: Incorrect ACK/NACK");

                if (address_nack !== !expected_ack)
                    $fatal(1, "FAIL: Incorrect NACK pulse");

                if (address_acked)
                    $display("[%0t] ADDRESS ACK", $time);
                else
                    $display("[%0t] ADDRESS NACK", $time);
            end

            if (address_nack)
                nack_events = nack_events + 1;
        end
    end

    // Generate START condition
    task i2c_start;
        begin
            controller_sda_low = 0;
            controller_scl_low = 0;
            #1000;

            controller_sda_low = 1;
            #1000;

            controller_scl_low = 1;
            #1000;
        end
    endtask

    // Send one I2C bit
    task send_bit(input logic bit_value);
        begin
            controller_scl_low = 1;
            controller_sda_low = !bit_value;
            #1000;

            controller_scl_low = 0;
            #1000;

            controller_scl_low = 1;
            #1000;
        end
    endtask

    // Ninth clock: sensor ACK or NACK
    task send_ack(input logic should_ack);
        begin
            controller_scl_low = 1;
            controller_sda_low = 0;

            sensor_sda_low = should_ack;
            #1000;

            controller_scl_low = 0;
            #1000;

            controller_scl_low = 1;
            #1000;

            sensor_sda_low = 0;
            #1000;
        end
    endtask

    // Generate STOP condition
    task i2c_stop;
        begin
            controller_scl_low = 1;
            controller_sda_low = 1;
            #1000;

            controller_scl_low = 0;
            #1000;

            controller_sda_low = 0;
            #1000;
        end
    endtask

    // Run one address transaction
    task run_transaction(input logic should_ack);
        begin
            expected_ack = should_ack;

            i2c_start();

            // Address 0x48 + WRITE = 0x90
            for (integer i = 7; i >= 0; i = i - 1)
                send_bit((8'h90 >> i) & 1'b1);

            send_ack(should_ack);
            i2c_stop();

            #1000;
        end
    endtask

    initial begin
        $dumpfile("sim/i2c_address.vcd");
        $dumpvars(0, tb_i2c_address_decoder);

        repeat (5) @(negedge clk);
        rst_n = 1;

        #1000;

        // TEST 1: Sensor exists and ACKs
        $display("TEST 1: Successful address ACK");
        run_transaction(1'b1);

        // TEST 2: Missing sensor causes NACK
        $display("TEST 2: Missing sensor NACK");
        run_transaction(1'b0);

        // Final checks
        if (address_events != 2)
            $fatal(1, "FAIL: Expected 2 addresses");

        if (ack_events != 2)
            $fatal(1, "FAIL: Expected 2 ACK-slot events");

        if (nack_events != 1)
            $fatal(1, "FAIL: Expected 1 address NACK");

        $display("--------------------------------");
        $display("PASS: Address decoding");
        $display("PASS: ACK detection");
        $display("PASS: Missing-device NACK");
        $display("PASS: Milestone 3");
        $display("--------------------------------");

        $finish;
    end

endmodule
