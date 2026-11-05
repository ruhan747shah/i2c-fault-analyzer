
`timescale 1ns/1ps

module tb_i2c_address_decoder;

    // 50 MHz FPGA clock
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

    logic [6:0] address;
    logic rw;
    logic address_valid;

    integer address_events = 0;

    i2c_address_decoder dut (
        .clk(clk),
        .rst_n(rst_n),
        .sda(sda),
        .scl(scl),
        .address(address),
        .rw(rw),
        .address_valid(address_valid)
    );

    // Observe decoder outputs
    always @(posedge clk) begin
        #1;

        if (address_valid) begin
            address_events = address_events + 1;

            $display(
                "Decoded address: 0x%02h, R/W=%0b",
                address, rw
            );

            if (address !== 7'h48 || rw !== 1'b0)
                $fatal(1, "Incorrect address decode");
        end
    end

    // Transmit one I2C bit
    task send_bit(input logic bit_value);
        begin
            controller_scl_low = 1;
            controller_sda_low = !bit_value;

            #1000;

            controller_scl_low = 0;
            #1000;

            controller_scl_low = 1;
            #1000;
        end
    endtask

    initial begin
        $dumpfile("sim/i2c_address.vcd");
        $dumpvars(0, tb_i2c_address_decoder);

        repeat (5) @(negedge clk);
        rst_n = 1;

        #1000;

        // START
        controller_sda_low = 1;
        #1000;
        controller_scl_low = 1;

        // Address 0x48 + write bit
        // 0x48 << 1 = 0x90
        for (integer i = 7; i >= 0; i = i - 1) begin
            send_bit((8'h90 >> i) & 1'b1);
        end

        // Sensor ACK on ninth SCL pulse
        controller_sda_low = 0;
        sensor_sda_low = 1;

        #1000;
        controller_scl_low = 0;
        #1000;
        controller_scl_low = 1;
        #1000;

        // Release SDA and generate STOP correctly
        controller_sda_low = 1;
        sensor_sda_low = 0;
        #1000;
        controller_scl_low = 0;
        #1000;
        controller_sda_low = 0;
        #1000;

        if (address_events != 1)
            $fatal(1, "Expected one address event");

        $display("PASS: I2C address decoder");
        $finish;
    end

endmodule
