
`timescale 1ns/1ps

module tb_i2c_event_logger;

    logic clk = 0;
    always #10 clk = ~clk;

    logic rst_n = 0;

    // Open-drain bus
    tri1 sda;
    tri1 scl;

    logic controller_sda_low = 0;
    logic controller_scl_low = 0;
    logic sensor_sda_low = 0;

    assign sda = controller_sda_low ? 1'b0 : 1'bz;
    assign sda = sensor_sda_low ? 1'b0 : 1'bz;
    assign scl = controller_scl_low ? 1'b0 : 1'bz;

    logic event_valid;
    logic [3:0] event_type;
    logic [7:0] event_data;
    logic [31:0] event_timestamp;

    integer event_count = 0;
    logic [31:0] last_timestamp = 0;

    // Event types
    localparam [3:0]
        EV_START         = 4'd1,
        EV_RESTART       = 4'd2,
        EV_STOP          = 4'd3,
        EV_ADDRESS       = 4'd4,
        EV_DATA          = 4'd5,
        EV_ADDR_ACK      = 4'd6,
        EV_DATA_ACK      = 4'd7,
        EV_ADDR_NACK     = 4'd8,
        EV_READ_END_NACK = 4'd9;

    i2c_event_logger dut (
        .clk(clk),
        .rst_n(rst_n),
        .sda(sda),
        .scl(scl),
        .event_valid(event_valid),
        .event_type(event_type),
        .event_data(event_data),
        .event_timestamp(event_timestamp)
    );

    // Check each decoded event
    task check_event(
        input logic [3:0] expected_type,
        input logic [7:0] expected_data
    );
        begin
            if (event_type !== expected_type)
                $fatal(1,
                    "Event %0d: expected type %0d, got %0d",
                    event_count, expected_type, event_type);

            if (event_data !== expected_data)
                $fatal(1,
                    "Event %0d: expected data %02h, got %02h",
                    event_count, expected_data, event_data);
        end
    endtask

    // Self-checking event sequence
    always @(posedge clk) begin
        #1;

        if (rst_n && event_valid) begin
            event_count = event_count + 1;

            $display(
                "TIME=%0d EVENT=%0d DATA=0x%02h",
                event_timestamp, event_type, event_data
            );

            if (event_count > 1 &&
                event_timestamp <= last_timestamp)
                $fatal(1, "Timestamps not increasing");

            last_timestamp = event_timestamp;

            case (event_count)
                // Successful register read
                1:  check_event(EV_START,         8'h00);
                2:  check_event(EV_ADDRESS,       8'h90);
                3:  check_event(EV_ADDR_ACK,      8'h00);
                4:  check_event(EV_DATA,          8'h01);
                5:  check_event(EV_DATA_ACK,      8'h00);
                6:  check_event(EV_RESTART,       8'h00);
                7:  check_event(EV_ADDRESS,       8'h91);
                8:  check_event(EV_ADDR_ACK,      8'h00);
                9:  check_event(EV_DATA,          8'h2A);
                10: check_event(EV_READ_END_NACK, 8'h00);
                11: check_event(EV_STOP,          8'h00);

                // Missing sensor
                12: check_event(EV_START,         8'h00);
                13: check_event(EV_ADDRESS,       8'hA0);
                14: check_event(EV_ADDR_NACK,     8'h00);
                15: check_event(EV_STOP,          8'h00);

                default:
                    $fatal(1, "Unexpected extra event");
            endcase
        end
    end

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

    task i2c_repeated_start;
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

            // Release SDA with SCL LOW
            controller_sda_low = 0;
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
        $dumpfile("sim/i2c_events.vcd");
        $dumpvars(0, tb_i2c_event_logger);

        repeat (5) @(negedge clk);
        rst_n = 1;
        #1000;

        $display("TEST 1: Register read");

        i2c_start();
        send_byte(8'h90, 0);
        send_ack(1, 1);

        send_byte(8'h01, 0);
        send_ack(1, 1);

        i2c_repeated_start();

        send_byte(8'h91, 0);
        send_ack(1, 1);

        send_byte(8'h2A, 1);
        send_ack(0, 0);
        i2c_stop();

        #1000;

        $display("TEST 2: Missing device");

        i2c_start();
        send_byte(8'hA0, 0);
        send_ack(0, 1);
        i2c_stop();

        #1000;

        if (event_count != 15)
            $fatal(1,
                "Expected 15 events, received %0d",
                event_count);

        $display("--------------------------------");
        $display("PASS: All 15 events decoded in order");
        $display("PASS: Event payloads verified");
        $display("PASS: Timestamps increasing");
        $display("PASS: Address NACK classified");
        $display("PASS: Normal read NACK classified");
        $display("PASS: MILESTONE 5");
        $display("--------------------------------");

        $finish;
    end

    // Prevent a hanging simulation
    initial begin
        #300000;
        $fatal(1, "Simulation timeout");
    end

endmodule
