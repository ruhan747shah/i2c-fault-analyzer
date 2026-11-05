
`timescale 1ns/1ps

module tb_i2c_fault_capture;

    logic clk = 0;
    always #10 clk = ~clk;  // 50 MHz

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

    // Logger outputs
    logic        event_valid;
    logic [3:0]  event_type;
    logic [7:0]  event_data;
    logic [31:0] event_timestamp;

    // Capture outputs
    logic       fault_triggered;
    logic       capture_done;
    logic [4:0] capture_count;

    logic [3:0]  read_index;
    logic        read_valid;
    logic [3:0]  read_type;
    logic [7:0]  read_data;
    logic [31:0] read_timestamp;

    integer total_events = 0;
    logic [31:0] previous_timestamp = 0;

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

    // Existing event logger
    i2c_event_logger logger (
        .clk(clk),
        .rst_n(rst_n),
        .sda(sda),
        .scl(scl),
        .event_valid(event_valid),
        .event_type(event_type),
        .event_data(event_data),
        .event_timestamp(event_timestamp)
    );

    // New circular capture memory
    i2c_fault_capture capture (
        .clk(clk),
        .rst_n(rst_n),
        .event_valid(event_valid),
        .event_type(event_type),
        .event_data(event_data),
        .event_timestamp(event_timestamp),
        .fault_triggered(fault_triggered),
        .capture_done(capture_done),
        .capture_count(capture_count),
        .read_index(read_index),
        .read_valid(read_valid),
        .read_type(read_type),
        .read_data(read_data),
        .read_timestamp(read_timestamp)
    );

    // Print every live event
    always @(posedge clk) begin
        #1;

        if (rst_n && event_valid) begin
            total_events = total_events + 1;

            $display(
                "[%0d] EVENT=%0d DATA=0x%02h TIME=%0d",
                total_events,
                event_type,
                event_data,
                event_timestamp
            );
        end
    end

    task i2c_start;
        begin
            controller_scl_low = 0;
            controller_sda_low = 0;
            sensor_sda_low = 0;
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

            // Release SDA while clock is low
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

    // Compare one captured event against expectation
    task check_capture(
        input integer index,
        input logic [3:0] expected_type,
        input logic [7:0] expected_data
    );
        begin
            read_index = index;
            #1;

            if (!read_valid)
                $fatal(1, "Capture entry %0d invalid",
                       index);

            if (read_type !== expected_type ||
                read_data !== expected_data)
                $fatal(1,
                    "Entry %0d: expected (%0d,%02h), got (%0d,%02h)",
                    index, expected_type, expected_data,
                    read_type, read_data);

            if (index > 0 &&
                read_timestamp <= previous_timestamp)
                $fatal(1,
                    "Capture timestamps not increasing");

            previous_timestamp = read_timestamp;

            $display(
                "CAPTURE[%0d] TIME=%0d TYPE=%0d DATA=0x%02h",
                index, read_timestamp, read_type, read_data
            );
        end
    endtask

    initial begin
        read_index = 0;

        $dumpfile("sim/i2c_fault_capture.vcd");
        $dumpvars(0, tb_i2c_fault_capture);

        repeat (5) @(negedge clk);
        rst_n = 1;
        #1000;

        // TEST 1: Successful register read
        $display("TEST 1: Successful read");

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

        if (fault_triggered)
            $fatal(1,
                "Normal read incorrectly triggered fault");

        // TEST 2: Missing sensor at 0x50
        $display("TEST 2: Missing sensor");

        i2c_start();
        send_byte(8'hA0, 0);
        send_ack(0, 1);

        #200;

        if (!fault_triggered)
            $fatal(1, "Address NACK did not trigger");

        if (capture_done)
            $fatal(1, "Capture froze too early");

        i2c_stop();
        #1000;

        // TEST 3: Subsequent successful write
        // Produces the remaining six post-trigger events
        $display("TEST 3: Successful write");

        i2c_start();
        send_byte(8'h90, 0);
        send_ack(1, 1);

        send_byte(8'hA5, 0);
        send_ack(1, 1);
        i2c_stop();

        #1000;

        if (!capture_done)
            $fatal(1, "Capture did not complete");

        if (capture_count !== 5'd16)
            $fatal(1,
                "Expected 16 captured events, got %0d",
                capture_count);

        $display("Checking frozen event buffer");

        // Eight events before address NACK
        check_capture(0,  EV_RESTART,       8'h00);
        check_capture(1,  EV_ADDRESS,       8'h91);
        check_capture(2,  EV_ADDR_ACK,      8'h00);
        check_capture(3,  EV_DATA,          8'h2A);
        check_capture(4,  EV_READ_END_NACK, 8'h00);
        check_capture(5,  EV_STOP,          8'h00);
        check_capture(6,  EV_START,         8'h00);
        check_capture(7,  EV_ADDRESS,       8'hA0);

        // Trigger event
        check_capture(8,  EV_ADDR_NACK,     8'h00);

        // Seven post-trigger events
        check_capture(9,  EV_STOP,          8'h00);
        check_capture(10, EV_START,         8'h00);
        check_capture(11, EV_ADDRESS,       8'h90);
        check_capture(12, EV_ADDR_ACK,      8'h00);
        check_capture(13, EV_DATA,          8'hA5);
        check_capture(14, EV_DATA_ACK,      8'h00);
        check_capture(15, EV_STOP,          8'h00);

        // Confirm new events do not overwrite frozen data
        i2c_start();
        i2c_stop();
        #1000;

        if (capture_count !== 5'd16 || !capture_done)
            $fatal(1, "Capture state changed after freeze");

        // Restart timestamp check for random-access readback
        previous_timestamp = 0;
        check_capture(8, EV_ADDR_NACK, 8'h00);

        $display("--------------------------------");
        $display("PASS: Eight pre-trigger events");
        $display("PASS: Address-NACK fault trigger");
        $display("PASS: Seven post-trigger events");
        $display("PASS: Timestamp ordering");
        $display("PASS: Frozen circular buffer");
        $display("PASS: MILESTONE 6");
        $display("--------------------------------");

        $finish;
    end

    initial begin
        #300000;
        $fatal(1, "Simulation timeout");
    end

endmodule
