
module i2c_address_decoder (
    input  logic clk,
    input  logic rst_n,
    input  logic sda,
    input  logic scl,

    output logic [6:0] address,
    output logic rw,
    output logic address_valid,

    // New ACK/NACK outputs
    output logic ack_valid,
    output logic address_acked,
    output logic address_nack
);

    // Synchronize incoming I2C signals
    logic sda_meta, sda_sync;
    logic scl_meta, scl_sync;
    logic scl_prev;

    logic start_pulse;
    logic stop_pulse;

    // Reuse START/STOP detector
    i2c_start_stop detector (
        .clk(clk),
        .rst_n(rst_n),
        .sda(sda),
        .scl(scl),
        .start_pulse(start_pulse),
        .stop_pulse(stop_pulse)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sda_meta <= 1'b1;
            sda_sync <= 1'b1;
            scl_meta <= 1'b1;
            scl_sync <= 1'b1;
            scl_prev <= 1'b1;
        end else begin
            sda_meta <= sda;
            sda_sync <= sda_meta;
            scl_meta <= scl;
            scl_sync <= scl_meta;
            scl_prev <= scl_sync;
        end
    end

    // SCL rising edge
    wire scl_rising = !scl_prev && scl_sync;

    // FSM states
    localparam IDLE     = 2'd0;
    localparam ADDRESS  = 2'd1;
    localparam ADDR_ACK = 2'd2;
    localparam DONE     = 2'd3;

    logic [1:0] state;
    logic [2:0] bit_count;
    logic [7:0] shift_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            bit_count <= 0;
            shift_reg <= 0;

            address <= 0;
            rw <= 0;

            address_valid <= 0;
            ack_valid <= 0;
            address_acked <= 0;
            address_nack <= 0;

        end else begin

            // Pulses are normally LOW
            address_valid <= 0;
            ack_valid <= 0;
            address_nack <= 0;

            // START or repeated START
            if (start_pulse) begin
                state <= ADDRESS;
                bit_count <= 0;
                shift_reg <= 0;
                address_acked <= 0;
            end

            // STOP ends transaction
            else if (stop_pulse) begin
                state <= IDLE;
            end

            else if (scl_rising) begin

                case (state)

                    ADDRESS: begin
                        shift_reg <= {
                            shift_reg[6:0],
                            sda_sync
                        };

                        if (bit_count == 7) begin
                            address <= shift_reg[6:0];
                            rw <= sda_sync;

                            address_valid <= 1'b1;
                            state <= ADDR_ACK;
                        end else begin
                            bit_count <= bit_count + 1'b1;
                        end
                    end

                    ADDR_ACK: begin
                        // SDA=0 -> ACK
                        // SDA=1 -> NACK

                        address_acked <= !sda_sync;
                        ack_valid <= 1'b1;

                        if (sda_sync)
                            address_nack <= 1'b1;

                        state <= DONE;
                    end

                    default: begin
                        // No action
                    end

                endcase
            end
        end
    end

endmodule
