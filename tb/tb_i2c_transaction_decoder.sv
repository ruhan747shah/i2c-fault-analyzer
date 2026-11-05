
`timescale 1ns/1ps

module tb_i2c_transaction_decoder;

    logic clk = 0;
    always #10 clk = ~clk;  // 50 MHz

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

    logic start_pulse, repeated_start, stop_pulse;
    logic [6:0] address;
    logic rw, address_valid;
    logic [7:0] data_byte;
    logic data_valid;
    logic ack_valid, ack_is_address, acked;
    logic address_nack, read_end_nack;

    integer start_count = 0;
    integer stop_count = 0;
    integer address_count = 0;
    integer data_count = 0;
    integer ack_count = 0;
    integer nack_count = 0;
    integer read_end_count = 0;
    integer repeated_count = 0;

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

    // Self-checking event monitor
    always @(posedge clk) begin
        #1;

        if (rst_n) begin

            if (start_pulse) begin
                start_count = start_count + 1;
                $display("[%0t] START", $time);
            end

            if (repeated_start) begin
                repeated_count = repeated_count + 1;
                $display("[%0t] REPEATED START", $time);
            end

            if (stop_pulse) begin
                stop_count = stop_count + 1;
                $display("[%0t] STOP", $time);
            end

            if (address_valid) begin
                address_count = address_count + 1;

                $display("[%0t] ADDRESS: 0x%02h RW=%0b",
                         $time, address, rw);

                case (address_count)
                    1: if (address !== 7'h48 || rw !== 0)
                           $fatal(1, "Wrong first address");

                    2: if (address !== 7'h48 || rw !== 1)
                           $fatal(1, "Wrong repeated-start address");

                    3: if (address !== 7'h50 || rw !== 0)
                           $fatal(1, "Wrong missing-device address");

                    default:
                        $fatal(1, "Unexpected address event");
                endcase
            end

            if (data_valid) begin
                data_count = data_count + 1;

                $display("[%0t] DATA: 0x%02h",
                         $time, data_byte);

                case (data_count)
                    1: if (data_byte !== 8'h01)
                           $fatal(1, "Wrong register byte");

                    2: if (data_byte !== 8'h2A)
                           $fatal(1, "Wrong sensor data");

                    default:
                        $fatal(1, "Unexpected data event");
                endcase
            end

            if (ack_valid) begin
                ack_count = ack_count + 1;

                $display("[%0t] %s %s", $time,
                    ack_is_address ? "ADDRESS" : "DATA",
                    acked ? "ACK" : "NACK");

                case (ack_count)
                    1, 3: if (!ack_is_address || !acked)
                              $fatal(1, "Expected address ACK");

                    2: if (ack_is_address || !acked)
                           $fatal(1, "Expected data ACK");

                    4: if (ack_is_address || acked)
                           $fatal(1, "Expected read-end NACK");

                    5: if (!ack_is_address || acked)
                           $fatal(1, "Expected address NACK");

                    default:
                        $fatal(1, "Unexpected ACK slot");
                endcase
            end

            if (address_nack) begin
                nack_count = nack_count + 1;
                $display("[%0t] FAULT: ADDRESS NACK", $time);
            end

            if (read_end_nack) begin
                read_end_count = read_end_count + 1;
                $display("[%0t] NORMAL: READ END NACK", $time);
            end
        end
    end

    // START: SDA falls while SCL is high
    task i2c_start;
        begin
            controller_sda_low = 0;
            sensor_sda_low = 0;
            controller_scl_low = 0;
            #500;

            controller_sda_low = 1;
            #500;

            controller_scl_low = 1;
            #500;
        end
    endtask

    // Repeated START: release SDA, raise SCL,
    // then pull SDA low
    task repeated_start_task;
        begin
            controller_scl_low = 1;
            controller_sda_low = 0;
            sensor_sda_low = 0;
            #500;

            controller_scl_low = 0;
            #500;

            controller_sda_low = 1;
            #500;

            controller_scl_low = 1;
            #500;
        end
    endtask

    // Send 8 bits MSB first
    task send_byte(
        input logic [7:0] value,
        input logic from_sensor
    );
        begin
            for (integer i = 7; i >= 0; i = i - 1) begin

                controller_scl_low = 1;

                if (from_sensor) begin
                    controller_sda_low = 0;
                    sensor_sda_low = !value[i];
                end else begin
                    sensor_sda_low = 0;
                    controller_sda_low = !value[i];
                end

                #500;
                controller_scl_low = 0;
                #500;
                controller_scl_low = 1;
                #500;
            end
        end
    endtask

    // Ninth clock: ACK=LOW, NACK=HIGH
    task send_ack(
        input logic do_ack,
        input logic from_sensor
    );
        begin
            controller_scl_low = 1;
            controller_sda_low = 0;
            sensor_sda_low = 0;

            if (do_ack) begin
                if (from_sensor)
                    sensor_sda_low = 1;
                else
                    controller_sda_low = 1;
            end

            #500;
            controller_scl_low = 0;
            #500;
            controller_scl_low = 1;
            #500;

            // IMPORTANT:
            // Release SDA before the next operation,
            // while SCL is LOW.
            controller_sda_low = 0;
            sensor_sda_low = 0;
            #500;
        end
    endtask

    // STOP: SDA rises while SCL is high
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
        $dumpfile("sim/i2c_transaction.vcd");
        $dumpvars(0, tb_i2c_transaction_decoder);

        repeat (5) @(negedge clk);
        rst_n = 1;
        #1000;

        // TEST 1: Sensor register read
        $display("TEST 1: Register read");

        i2c_start();

        send_byte(8'h90, 0);
        send_ack(1, 1);

        send_byte(8'h01, 0);
        send_ack(1, 1);

        repeated_start_task();

        send_byte(8'h91, 0);
        send_ack(1, 1);

        send_byte(8'h2A, 1);
        send_ack(0, 0);

        i2c_stop();
        #1000;

        // TEST 2: Missing sensor
        $display("TEST 2: Missing sensor");

        i2c_start();

        send_byte(8'hA0, 0);
        send_ack(0, 1);

        i2c_stop();
        #1000;

        // Final assertions
        if (start_count != 3)
            $fatal(1, "Expected 3 STARTs, got %0d",
                   start_count);

        if (stop_count != 2)
            $fatal(1, "Expected 2 STOPs, got %0d",
                   stop_count);

        if (address_count != 3)
            $fatal(1, "Expected 3 addresses, got %0d",
                   address_count);

        if (data_count != 2)
            $fatal(1, "Expected 2 data bytes, got %0d",
                   data_count);

        if (ack_count != 5)
            $fatal(1, "Expected 5 ACK slots, got %0d",
                   ack_count);

        if (nack_count != 1)
            $fatal(1, "Expected 1 address NACK");

        if (read_end_count != 1)
            $fatal(1, "Expected 1 normal read NACK");

        if (repeated_count != 1)
            $fatal(1, "Expected 1 repeated START");

        $display("--------------------------------");
        $display("PASS: Address decoding");
        $display("PASS: Data byte decoding");
        $display("PASS: Repeated START");
        $display("PASS: Address NACK detection");
        $display("PASS: Normal read-end NACK");
        $display("PASS: MILESTONE 4");
        $display("--------------------------------");

        $finish;
    end

endmodule
