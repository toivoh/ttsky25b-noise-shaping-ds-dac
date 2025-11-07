`default_nettype none
`timescale 1ns / 1ps

module tb_delta_sigma #(parameter IN_BITS = 16, FRAC_BITS = 8, OUT_BITS = 9) ();
	// Dump the signals to a VCD file. You can view it with gtkwave or surfer.
	initial begin
		$dumpfile("tb_delta_sigma.vcd");
		$dumpvars(0, tb_delta_sigma);
		#1;
	end

	// Wire up the inputs and outputs:
	reg clk;
	reg rst_n;
	wire reset = !rst_n;

	reg [IN_BITS-1:0] u = 0;
	reg force_err = 0;
	reg [FRAC_BITS-1:0] forced_err_value;
	reg [3:0] coeff_choice = 0;

	wire [OUT_BITS-1:0] y;
	wire y_valid;
	delta_sigma_modulator #(.IN_BITS(IN_BITS), .FRAC_BITS(FRAC_BITS), .OUT_BITS(OUT_BITS)) modulator(
		.clk(clk), .reset(reset), .en(1'b1), .reset_lfsr(0),
		.noise_mode(0), .n_decorrelate(0), .coeff_choice(coeff_choice),
		.u(u), .u_rshift(0), .y(y), .y_valid_out(y_valid),
		.force_err(force_err), .forced_err_value(forced_err_value)
	);

	reg [OUT_BITS-1:0] y_sampled;
	reg [15:0] acc_sampled;
	always_ff @(posedge clk) begin
		if (y_valid) y_sampled <= y;
		if (y_valid) acc_sampled <= modulator.acc;
	end

	int counter = 0;
	int sample_counter = 0;
	always_ff @(posedge clk) counter <= reset ? 0 : counter + 1;
	always_ff @(posedge clk) sample_counter <= reset ? 0 : sample_counter + y_valid;

	localparam SREG_BITS = 16;

	wire [SREG_BITS-1:0] sreg0 = modulator.sreg[0];
	wire [SREG_BITS-1:0] sreg1 = modulator.sreg[1];
	wire [SREG_BITS-1:0] sreg2 = modulator.sreg[2];
endmodule
