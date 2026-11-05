
module i2c_fault_capture (
    input  logic clk,
    input  logic rst_n,

    // Events from the event logger
    input  logic        event_valid,
    input  logic [3:0]  event_type,
    input  logic [7:0]  event_data,
    input  logic [31:0] event_timestamp,

    // Capture status
    output logic        fault_triggered,
    output logic        capture_done,
    output logic [4:0]  capture_count,

    // Read back captured events in time order
    input  logic [3:0]  read_index,
    output logic        read_valid,
    output logic [3:0]  read_type,
    output logic [7:0]  read_data,
    output logic [31:0] read_timestamp
);

    localparam [3:0] EV_ADDR_NACK = 4'd8;

    // 16-entry circular event memory
    logic [3:0]  type_mem [0:15];
    logic [7:0]  data_mem [0:15];
    logic [31:0] time_mem [0:15];

    logic [3:0] write_ptr;
    logic [3:0] start_ptr;

    // Number of valid historical events, max 8
    logic [3:0] history_count;

    // Number of post-trigger events still needed
    logic [3:0] post_remaining;

    logic [3:0] read_addr;

    // Four-bit pointer arithmetic wraps modulo 16
    assign read_addr = start_ptr + read_index;

    // Read only after capture is complete
    assign read_valid =
        capture_done &&
        ({1'b0, read_index} < capture_count);

    assign read_type =
        read_valid ? type_mem[read_addr] : 4'd0;

    assign read_data =
        read_valid ? data_mem[read_addr] : 8'd0;

    assign read_timestamp =
        read_valid ? time_mem[read_addr] : 32'd0;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_ptr <= 4'd0;
            start_ptr <= 4'd0;

            history_count <= 4'd0;
            post_remaining <= 4'd0;

            fault_triggered <= 1'b0;
            capture_done <= 1'b0;
            capture_count <= 5'd0;

        end else if (event_valid && !capture_done) begin

            // Store current event
            type_mem[write_ptr] <= event_type;
            data_mem[write_ptr] <= event_data;
            time_mem[write_ptr] <= event_timestamp;

            // Automatically wrap after entry 15
            write_ptr <= write_ptr + 1'b1;

            if (!fault_triggered) begin

                if (event_type == EV_ADDR_NACK) begin

                    // Trigger only on ADDRESS NACK
                    fault_triggered <= 1'b1;

                    // Oldest retained event
                    start_ptr <= write_ptr -
                                 history_count[3:0];

                    // Historical events + trigger
                    capture_count <=
                        {1'b0, history_count} + 5'd1;

                    // Collect seven subsequent events
                    post_remaining <= 4'd7;

                end else begin

                    // Keep the last eight pre-trigger events
                    if (history_count < 4'd8)
                        history_count <=
                            history_count + 1'b1;

                end

            end else begin

                // Post-trigger capture
                capture_count <= capture_count + 1'b1;

                if (post_remaining == 4'd1) begin
                    post_remaining <= 4'd0;
                    capture_done <= 1'b1;
                end else begin
                    post_remaining <=
                        post_remaining - 1'b1;
                end

            end
        end
    end

endmodule
