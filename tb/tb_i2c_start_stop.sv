
`timescale 1ns/1ps

module tb_i2c_start_stop;

    // 50 MHz FPGA clock
    logic clk = 0;
    always #10 clk = ~clk;

    logic rst_n = 0;

    // I2C uses open-drain signals.
    // Devices pull LOW or release the line.
    tri1 sda;
    tri1 scl;

    logic sda_low = 0;
    logic scl_low = 0;

    assign sda = sda_low ? 1'b0 : 1'bz;
    assign scl = scl_low ? 1'b0 : 1'bz;

    // Outputs from our FPGA monitor
    logic start_pulse;
    logic stop_pulse;

    // Count detected events
    integer start_count = 0;
    integer stop_count = 0;

    // Instantiate our design
    i2c_start_stop dut (
        .clk(clk),
        .rst_n(rst_n),
        .sda(sda),
        .scl(scl),
        .start_pulse(start_pulse),
        .stop_pulse(stop_pulse)
    );

    // Monitor outputs
    always @(posedge clk) begin
        #1;
        if (start_pulse) begin
            start_count = start_count + 1;
            $display("START detected at %0t", $time);
        end

        if (stop_pulse) begin
            stop_count = stop_count + 1;
            $display("STOP detected at %0t", $time);
        end
    end

    initial begin
        // Save waveform for GTKWave
        $dumpfile("sim/i2c_start_stop.vcd");
        $dumpvars(0, tb_i2c_start_stop);

        // Release reset
        repeat (5) @(negedge clk);
        rst_n = 1;

        #200;

        // START: SDA goes LOW while SCL is HIGH
        sda_low = 1;
        #200;

        // Pull SCL LOW
        scl_low = 1;
        #200;

        // Change SDA while SCL LOW (ordinary data)
        sda_low = 0;
        #200;
        sda_low = 1;
        #200;

        // Release SCL to HIGH
        scl_low = 0;
        #200;

        // STOP: SDA goes HIGH while SCL HIGH
        sda_low = 0;
        #200;

        // Check expected number of events
        if (start_count != 1 || stop_count != 1) begin
            $fatal(1,
                "FAIL: START=%0d STOP=%0d",
                start_count, stop_count);
        end

        $display("PASS: START/STOP detection");
        $finish;
    end

endmodule
