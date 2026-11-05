
module i2c_address_decoder (
    input  logic clk,
    input  logic rst_n,
    input  logic sda,
    input  logic scl,

    output logic [6:0] address,
    output logic rw,
    output logic address_valid
);

    // Synchronize incoming I2C signals
    logic sda_meta, sda_sync;
    logic scl_meta, scl_sync;
    logic scl_prev;

    // START/STOP pulses from milestone 1
    logic start_pulse;
    logic stop_pulse;

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

    // Detect rising edge of SCL
    wire scl_rising = !scl_prev && scl_sync;

    // Decoder states
    localparam IDLE    = 2'd0;
    localparam ADDRESS = 2'd1;
    localparam DONE    = 2'd2;

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
        end else begin

            // Default: pulse remains LOW
            address_valid <= 0;

            // START or repeated START
            if (start_pulse) begin
                state <= ADDRESS;
                bit_count <= 0;
                shift_reg <= 0;
            end

            // STOP ends the transaction
            else if (stop_pulse) begin
                state <= IDLE;
            end

            // Read one bit on each SCL rising edge
            else if (state == ADDRESS && scl_rising) begin

                shift_reg <= {shift_reg[6:0], sda_sync};

                if (bit_count == 7) begin
                    // First 7 bits are address
                    address <= shift_reg[6:0];

                    // Eighth bit is read/write
                    rw <= sda_sync;

                    // Complete address received
                    address_valid <= 1'b1;
                    state <= DONE;
                end else begin
                    bit_count <= bit_count + 1'b1;
                end
            end
        end
    end

endmodule
