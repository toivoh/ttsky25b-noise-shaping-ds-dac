`default_nettype none
`timescale 1ns / 1ps

module tb_pulse_width_modulator #(parameter BITS = 11) ();
	// Dump the signals to a VCD file. You can view it with gtkwave or surfer.
	initial begin
		$dumpfile("tb_pulse_width_modulator.vcd");
		$dumpvars(0, tb_pulse_width_modulator);
		#1;
	end

	// Wire up the inputs and outputs:
	reg clk;
	reg rst_n;
	wire reset = !rst_n;

	reg dual_slope_en = 0;
	reg double_slope_en = 0;

	reg [BITS-1:0] compare_max = 0;
	reg [BITS-1:0] pulse_width = 0;

	wire pulse_done, pwm_out;

	pulse_width_modulator #(.BITS(BITS)) pw_modulator(
		.clk(clk), .reset(reset),
		.dual_slope_en(dual_slope_en), .double_slope_en(double_slope_en),
		.compare_max(compare_max),
		.pulse_width(pulse_width),
		.pulse_done(pulse_done),
		.pwm_out(pwm_out)
	);

	int counter = 0;
	int sample_counter = 0;
	always_ff @(posedge clk) counter <= reset ? 0 : counter + 1;
	always_ff @(posedge clk) sample_counter <= reset ? 0 : sample_counter + pulse_done;
endmodule
