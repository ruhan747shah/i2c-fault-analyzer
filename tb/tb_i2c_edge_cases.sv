
`timescale 1ns/1ps

module tb_i2c_edge_cases;

    logic clk = 0;
    always #10 clk = ~clk;  // 50 MHz

    logic rst_n = 0;

    // Open-drain I2C bus
    tri1 sda;
    tri1 scl;

    logic controller_sda_low = 0;
    logic controller_scl_low = 0;
    logic sensor_sda_low = 0;
    logic sensor_scl_low = 0;

    assign sda = controller_sda_low ? 1'b0 : 1'bz;
    assign sda = sensor_sda_low ? 1'b0 : 1'bz;

    assign scl = controller_scl_low ? 1'b0 : 1'bz;
    assign scl = sensor_scl_low ? 1'b0 : 1'bz;

    logic start_pulse, repeated_start, stop_pulse;
    logic [6:0] address;
    logic rw, address_valid;
    logic [7:0] data_byte;
    logic data_valid;
    logic ack_valid, ack_is_address, acked;
    logic address_nack, read_end_nack;

    integer address_count = 0;
    integer data_count = 0;
    integer ack_count = 0;
    integer start_count = 0;
    integer stop_count = 0;
    integer nack_count = 0;

    // Expected phase:
    // 0 = clock stretching test
    // 1 = interrupted transaction
    // 2 = recovery after reset
    integer phase = 0;

    i2c_transaction_decoder dut (
        .clk(clk),
        .rst_n(rst_n),
        .sda(sda),
        .scl(scl),
        .start_pulse(start_pulse),
        .repeated_start(repeated_start),
        .stop_pulse(stop_pulse),
        .address(address),
        .rw(rw),
        .address_valid(address_valid),
        .data_byte(data_byte),
        .data_valid(data_valid),
        .ack_valid(ack_valid),
        .ack_is_address(ack_is_address),
        .acked(acked),
        .address_nack(address_nack),
        .read_end_nack(read_end_nack)
    );

    always @(posedge clk) begin
        #1;
        if (rst_n) begin

            if (start_pulse)
                start_count = start_count + 1;

            if (stop_pulse)
                stop_count = stop_count + 1;

            if (repeated_start)
                $fatal(1, "Unexpected repeated START");

            if (address_nack || read_end_nack) begin
                nack_count = nack_count + 1;
                $fatal(1, "Unexpected NACK");
            end

            if (address_valid) begin
                address_count = address_count + 1;

                if (address !== 7'h48 || rw !== 1'b0)
                    $fatal(1, "Incorrect address");

                if (phase == 1)
                    $fatal(1, "Address completed before reset");

                $display("[%0t] ADDRESS 0x%02h",
                         $time, address);
            end

            if (data_valid) begin
                data_count = data_count + 1;

                if (phase == 0 && data_byte !== 8'hA5)
                    $fatal(1, "Wrong stretched data");

                if (phase == 2 && data_byte !== 8'h3C)
                    $fatal(1, "Wrong recovery data");

                if (phase == 1)
                    $fatal(1, "Unexpected interrupted data");

                $display("[%0t] DATA 0x%02h",
                         $time, data_byte);
            end

            if (ack_valid) begin
                ack_count = ack_count + 1;

                if (!acked)
                    $fatal(1, "Expected ACK");
            end
        end
    end

    task i2c_start;
        begin
            controller_scl_low = 0;
            controller_sda_low = 0;
            sensor_sda_low = 0;
            sensor_scl_low = 0;
            #500;

            controller_sda_low = 1;
            #500;
            controller_scl_low = 1;
            #500;
        end
    endtask

    // Send a bit, optionally with sensor clock stretching
    task send_bit(
        input logic value,
        input logic stretch
    );
        begin
            controller_scl_low = 1;
            controller_sda_low = !value;
            sensor_sda_low = 0;
            #500;

            if (stretch)
                sensor_scl_low = 1;

            // Controller releases SCL
            controller_scl_low = 0;

            if (stretch) begin
                #2000;

                if (scl !== 1'b0)
                    $fatal(1, "Stretch failed to hold SCL low");

                // Target releases SCL
                sensor_scl_low = 0;
            end

            #500;

            if (scl !== 1'b1)
                $fatal(1, "SCL failed to rise");

            controller_scl_low = 1;
            #500;
        end
    endtask

    task send_byte(
        input logic [7:0] value,
        input logic stretch
    );
        begin
            for (integer i = 7; i >= 0; i = i - 1)
                send_bit(value[i], stretch);
        end
    endtask

    task send_ack;
        begin
            controller_scl_low = 1;
            controller_sda_low = 0;
            sensor_sda_low = 1;
            #500;

            controller_scl_low = 0;
            #500;

            controller_scl_low = 1;
            #500;

            sensor_sda_low = 0;
            #500;
        end
    endtask

    task i2c_stop;
        begin
            controller_scl_low = 1;
            controller_sda_low = 1;
            sensor_sda_low = 0;
            #500;

            controller_scl_low = 0;
            #500;

            controller_sda_low = 0;
            #500;
        end
    endtask

    initial begin
        $dumpfile("sim/i2c_edge_cases.vcd");
        $dumpvars(0, tb_i2c_edge_cases);

        repeat (5) @(negedge clk);
        rst_n = 1;
        #1000;

        // TEST 1: Clock stretching
        $display("TEST 1: Clock stretching");

        phase = 0;
        i2c_start();

        send_byte(8'h90, 1);
        send_ack();

        send_byte(8'hA5, 1);
        send_ack();

        i2c_stop();
        #1000;

        if (address_count != 1 || data_count != 1 ||
            ack_count != 2 || start_count != 1 ||
            stop_count != 1)
            $fatal(1, "FAIL: Clock stretching counts");

        $display("PASS: Clock stretching");

        // TEST 2: Reset halfway through an address
        $display("TEST 2: Reset during transaction");

        phase = 1;
        i2c_start();

        // Send only four address bits
        send_bit(1'b1, 0);
        send_bit(1'b0, 0);
        send_bit(1'b0, 0);
        send_bit(1'b1, 0);

        // Reset analyzer mid-transaction
        controller_scl_low = 1;
        rst_n = 0;

        repeat (5) @(negedge clk);

        // Return bus to idle while reset is asserted
        controller_sda_low = 0;
        controller_scl_low = 0;
        sensor_sda_low = 0;
        sensor_scl_low = 0;

        repeat (10) @(negedge clk);

        rst_n = 1;
        #500;

        if (address_valid || data_valid ||
            ack_valid || address_nack)
            $fatal(1, "Stale event after reset");

        $display("PASS: Reset during transaction");

        // TEST 3: New transaction after reset
        $display("TEST 3: Recovery after reset");

        phase = 2;

        // Reset clears internal state, not test counters
        address_count = 0;
        data_count = 0;
        ack_count = 0;
        start_count = 0;
        stop_count = 0;
        nack_count = 0;

        i2c_start();

        send_byte(8'h90, 0);
        send_ack();

        send_byte(8'h3C, 0);
        send_ack();

        i2c_stop();
        #1000;

        if (address_count != 1)
            $fatal(1, "Expected 1 recovered address");

        if (data_count != 1)
            $fatal(1, "Expected 1 recovered data byte");

        if (ack_count != 2)
            $fatal(1, "Expected 2 ACKs");

        if (start_count != 1 || stop_count != 1)
            $fatal(1, "Unexpected START/STOP counts");

        if (nack_count != 0)
            $fatal(1, "Unexpected fault after reset");

        $display("PASS: Recovery after reset");
        $display("--------------------------------");
        $display("PASS: MILESTONE 7");
        $display("--------------------------------");

        $finish;
    end

    initial begin
        #500000;
        $fatal(1, "Simulation timeout");
    end

endmodule
