module i2c_analyzer_top (
    input  logic clk,
    input  logic rst_n,
    input  logic sda,
    input  logic scl,

    output logic fault_triggered,
    output logic capture_done,
    output logic [4:0] capture_count,

    input  logic [3:0] read_index,
    output logic read_valid,
    output logic [3:0] read_type,
    output logic [7:0] read_data,
    output logic [31:0] read_timestamp
);

    logic event_valid;
    logic [3:0] event_type;
    logic [7:0] event_data;
    logic [31:0] event_timestamp;

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

endmodule
