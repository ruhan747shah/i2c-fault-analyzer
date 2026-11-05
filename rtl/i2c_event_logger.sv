
module i2c_event_logger (
    input  logic clk,
    input  logic rst_n,
    input  logic sda,
    input  logic scl,

    output logic        event_valid,
    output logic [3:0]  event_type,
    output logic [7:0]  event_data,
    output logic [31:0] event_timestamp
);

    // Event identifiers
    localparam [3:0]
        EV_START         = 4'd1,
        EV_RESTART       = 4'd2,
        EV_STOP          = 4'd3,
        EV_ADDRESS       = 4'd4,
        EV_DATA          = 4'd5,
        EV_ADDR_ACK      = 4'd6,
        EV_DATA_ACK      = 4'd7,
        EV_ADDR_NACK     = 4'd8,
        EV_READ_END_NACK = 4'd9,
        EV_DATA_NACK     = 4'd10;

    // Signals from the transaction decoder
    logic start_pulse;
    logic repeated_start;
    logic stop_pulse;

    logic [6:0] address;
    logic rw;
    logic address_valid;

    logic [7:0] data_byte;
    logic data_valid;

    logic ack_valid;
    logic ack_is_address;
    logic acked;

    logic address_nack;
    logic read_end_nack;

    // System-clock timestamp counter
    logic [31:0] timestamp_counter;

    // Instantiate our Milestone 4 decoder
    i2c_transaction_decoder decoder (
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

    // Timestamp counter
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            timestamp_counter <= 32'd0;
        else
            timestamp_counter <= timestamp_counter + 1'b1;
    end

    // Convert decoded signals into events
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            event_valid <= 1'b0;
            event_type <= 4'd0;
            event_data <= 8'd0;
            event_timestamp <= 32'd0;
        end else begin

            // One-cycle event pulse
            event_valid <= 1'b0;

            // Repeated START is also a START, so
            // check this before ordinary START.
            if (repeated_start) begin
                event_valid <= 1'b1;
                event_type <= EV_RESTART;
                event_data <= 8'd0;
            end

            else if (start_pulse) begin
                event_valid <= 1'b1;
                event_type <= EV_START;
                event_data <= 8'd0;
            end

            else if (stop_pulse) begin
                event_valid <= 1'b1;
                event_type <= EV_STOP;
                event_data <= 8'd0;
            end

            else if (address_valid) begin
                event_valid <= 1'b1;
                event_type <= EV_ADDRESS;

                // 7-bit address + R/W bit
                event_data <= {address, rw};
            end

            else if (data_valid) begin
                event_valid <= 1'b1;
                event_type <= EV_DATA;
                event_data <= data_byte;
            end

            else if (ack_valid) begin
                event_valid <= 1'b1;
                event_data <= 8'd0;

                if (ack_is_address) begin
                    if (acked)
                        event_type <= EV_ADDR_ACK;
                    else
                        event_type <= EV_ADDR_NACK;
                end else begin
                    if (acked)
                        event_type <= EV_DATA_ACK;
                    else if (read_end_nack)
                        event_type <= EV_READ_END_NACK;
                    else
                        event_type <= EV_DATA_NACK;
                end
            end

            // Timestamp whenever a decoded event occurs
            if (repeated_start || start_pulse ||
                stop_pulse || address_valid ||
                data_valid || ack_valid) begin

                event_timestamp <= timestamp_counter;
            end
        end
    end

endmodule
