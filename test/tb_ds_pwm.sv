`default_nettype none
`timescale 1ns / 1ps

module tb_ds_pwm #(parameter IN_BITS = 16, FRAC_BITS = 8, PWM_BITS = 9) ();
	// Dump the signals to a VCD file. You can view it with gtkwave or surfer.
	initial begin
		$dumpfile("tb_ds_pwm.vcd");
		$dumpvars(0, tb_ds_pwm);
		#1;
	end

	// Wire up the inputs and outputs:
	reg clk;
	reg rst_n;
	wire reset = !rst_n;

	reg [IN_BITS-1:0] u = 0;
	reg dual_slope_en = 0;
	reg double_slope_en = 0;
	reg [PWM_BITS-1:0] compare_max = 0;


	wire pulse_done, pwm_out;
	delta_sigma_pw_modulator #(.IN_BITS(IN_BITS), .FRAC_BITS(FRAC_BITS), .PWM_BITS(PWM_BITS)) modulator(
		.clk(clk), .reset(reset),
		.u(u),
		.dual_slope_en(dual_slope_en), .double_slope_en(double_slope_en), .compare_max(compare_max),
		.pulse_done(pulse_done), .pwm_out(pwm_out)
	);

	reg [PWM_BITS-1:0] y_sampled;
	//reg [15:0] acc_sampled;
	always_ff @(posedge clk) begin
		if (modulator.y_valid) y_sampled <= modulator.y;
		//if (y_valid) acc_sampled <= modulator.acc;
	end


	int counter = 0;
	int sample_counter = 0;
	always_ff @(posedge clk) counter <= reset ? 0 : counter + 1;
	always_ff @(posedge clk) sample_counter <= reset ? 0 : sample_counter + pulse_done;

	wire signed [FRAC_BITS-1:0] sreg0 = modulator.ds_mod.sreg[0];
endmodule
