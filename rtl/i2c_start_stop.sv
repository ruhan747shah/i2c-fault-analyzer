
module i2c_start_stop (
    input  logic clk,
    input  logic rst_n,
    input  logic sda,
    input  logic scl,

    output logic start_pulse,
    output logic stop_pulse
);

    // 1. Synchronizer registers
    logic sda_meta, sda_sync;
    logic scl_meta, scl_sync;

    // 2. Previous synchronized values
    logic sda_prev;
    logic scl_prev;

    // 3. Synchronize SDA and SCL to the FPGA clock
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sda_meta <= 1'b1;
            sda_sync <= 1'b1;
            scl_meta <= 1'b1;
            scl_sync <= 1'b1;

            sda_prev <= 1'b1;
            scl_prev <= 1'b1;
        end
        else begin
            sda_meta <= sda;
            sda_sync <= sda_meta;

            scl_meta <= scl;
            scl_sync <= scl_meta;

            sda_prev <= sda_sync;
            scl_prev <= scl_sync;
        end
    end

    // 4. Detect START and STOP conditions
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            start_pulse <= 1'b0;
            stop_pulse  <= 1'b0;
        end
        else begin
            // START: SDA falls while SCL remains HIGH
            start_pulse <=
                sda_prev && !sda_sync &&
                scl_prev && scl_sync;

            // STOP: SDA rises while SCL remains HIGH
            stop_pulse <=
                !sda_prev && sda_sync &&
                scl_prev && scl_sync;
        end
    end

endmodule
