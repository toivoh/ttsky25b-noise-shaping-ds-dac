/*
 * Copyright (c) 2025 Toivo Henningsson
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

`define SRC2_SEL_U    0
`define SRC2_SEL_SREG 1

module delta_sigma_modulator #(
		parameter IN_BITS = 16,
		FRAC_BITS = 11,
		OUT_BITS = 7, // should include one extra bit for noise
		NUM_TAPS = 4,
		SHIFT_COUNT_BITS = 4, // also used for internal shifting, but only 2 bits needed for it for now
		MAX_LEFT_SHIFT = 2
	) (
		input wire clk, reset, en,

		input wire [IN_BITS-1:0] u, // input signal
		input [SHIFT_COUNT_BITS-1:0] u_rshift,
		output wire y_valid_out,
		output wire [OUT_BITS-1:0] y, // output signal

		// for testing
		input wire force_err,
		input wire [FRAC_BITS-1:0] forced_err_value
	);

	localparam FULL_BITS = IN_BITS+1;
	localparam SREG_LEN = NUM_TAPS-1;
	localparam ACC_BITS = FRAC_BITS + NUM_TAPS;

	localparam STATE_BITS = 4;

	genvar i;


	reg last_state; // not a register

	reg [STATE_BITS-1:0] state;
	always_ff @(posedge clk) begin
		if (reset) state <= 0;
		else if (en) begin
			if (last_state) state <= 0; // TODO: wait for next sample
			else state <= state + 1;
		end
	end

	// Contol signals
	// not registers
	reg src2_sel; // TODO: need more than 1 bit?
	reg inv_src2, inv_acc;
	// Only shift sreg when shift_sreg=1. If rotate_sreg=1, connect the input to the output to be able to rotate through the contents
	reg [SHIFT_COUNT_BITS-1:0] rshift_count;
	reg shift_sreg, rotate_sreg;
	reg y_valid;
	always_comb begin
		src2_sel = `SRC2_SEL_SREG;
		inv_src2 = 0; inv_acc = 0;
		rshift_count = 'X;
		shift_sreg = 0;
		rotate_sreg = 1;
		y_valid = 0;
		last_state = 0;

		/*
		// For NUM_TAPS = 2
		case (state)
			0: begin
				// Read new input, produce new output
				src2_sel = `SRC2_SEL_U;
				rshift_count = u_rshift;
				shift_sreg = 1; rotate_sreg = 0;
				y_valid = 1;
			end
			1: begin
				// [2 -1]
				inv_acc = 1;
				rshift_count = MAX_LEFT_SHIFT - 1; // *2

				last_state = 1;
			end
		endcase
		*/
		/*
		// For NUM_TAPS = 3
		case (state)
			0: begin
				// Read new input, produce new output
				src2_sel = `SRC2_SEL_U;
				rshift_count = u_rshift;
				shift_sreg = 1; rotate_sreg = 0;
				y_valid = 1;
			end
			// [-3 1]
			1: begin
				inv_acc = 0; inv_src2 = 1;
				rshift_count = MAX_LEFT_SHIFT - 1; // *2
			end
			2: begin
				inv_acc = 0; inv_src2 = 1;
				rshift_count = MAX_LEFT_SHIFT - 0; // *1
				shift_sreg = 1;
			end
			// [3]
			3: begin
				inv_acc = 0; inv_src2 = 0;
				rshift_count = MAX_LEFT_SHIFT - 1; // *2
			end
			4: begin
				inv_acc = 0; inv_src2 = 0;
				rshift_count = MAX_LEFT_SHIFT - 0; // *1
				shift_sreg = 1;

				last_state = 1;
			end
		endcase
		*/
		// For NUM_TAPS = 4
		case (state)
			0: begin
				// Read new input, produce new output
				src2_sel = `SRC2_SEL_U;
				rshift_count = u_rshift;
				shift_sreg = 1; rotate_sreg = 0;
				y_valid = 1;
			end
			1: begin
				// [4 -1]
				inv_acc = 1;
				rshift_count = MAX_LEFT_SHIFT - 2; // *4
				shift_sreg = 1;
			end
			// [-6]
			2: begin
				inv_acc = 0; inv_src2 = 1;
				rshift_count = MAX_LEFT_SHIFT - 2; // *4
			end
			3: begin
				inv_acc = 0; inv_src2 = 1;
				rshift_count = MAX_LEFT_SHIFT - 1; // *2
				shift_sreg = 1;
			end
			4: begin
				// [4]
				rshift_count = MAX_LEFT_SHIFT - 2; // *4
				shift_sreg = 1;

				last_state = 1;
			end
		endcase
	end

	assign y_valid_out = y_valid;


	wire signed [ACC_BITS-1:0] next_acc;
	reg signed [ACC_BITS-1:0] acc;
	(* mem2reg *) reg signed [FRAC_BITS-1:0] sreg[SREG_LEN];
	wire signed [FRAC_BITS-1:0] sreg_out = sreg[SREG_LEN-1];

	always_ff @(posedge clk) begin
		if (reset) acc <= 0;
		else if (en) acc <= next_acc;
	end

	wire [FRAC_BITS-1:0] sreg_in;
	wire [FRAC_BITS-1:0] sreg_next[SREG_LEN];
	generate
		assign sreg_next[0] = sreg_in;
		for (i = 0; i < SREG_LEN-1; i++) begin
			assign sreg_next[i+1] = sreg[i];
		end

		for (i = 0; i < SREG_LEN; i++) begin
			always_ff @(posedge clk) begin
				if (reset) sreg[i] <= 0;
				else if (en && shift_sreg) sreg[i] <= sreg_next[i];
			end
		end
	endgenerate

	// not a register
	reg signed [FULL_BITS-1:0] src2;
	always_comb begin
		case (src2_sel)
			`SRC2_SEL_U: src2 = u;
			`SRC2_SEL_SREG: begin
				// TODO: reuse shifter for u as well?
				src2 = $signed(sreg_out);
				src2 <<= MAX_LEFT_SHIFT;
			end
		endcase
		src2 = $signed(src2) >>> rshift_count;
		if (inv_src2) src2 = ~src2;
	end

	wire [FULL_BITS-1:0] sum = (inv_acc ? ~acc : acc) + src2 + $signed({1'b0, inv_acc | inv_src2});

	wire signed [ACC_BITS-1:0] next_acc_sum = sum[ACC_BITS-1:0];
	wire signed [ACC_BITS-1:0] next_acc_sreg = sreg_out;
	assign next_acc = (shift_sreg && !rotate_sreg) ? next_acc_sreg : next_acc_sum;

	assign y = sum[FULL_BITS-1:FRAC_BITS];

	// Invert top bit so that it looks like we computed acc + u - (1 << (FRAC_BITS-1)) and round to nearest output,
	// instead of acc + u and round down, so that the error becomes signed (and smaller in worst case magnitude).
	wire signed [FRAC_BITS-1:0] err = sum[FRAC_BITS-1:0] ^ (1 << (FRAC_BITS-1));
	wire signed [FRAC_BITS-1:0] err_eff = force_err ? forced_err_value : err;

	assign sreg_in = rotate_sreg ? sreg_out : err_eff;
endmodule : delta_sigma_modulator


module delta_sigma_pw_modulator #(
		parameter IN_BITS = 16,
		FRAC_BITS = 11,
		PWM_BITS = 7, // should include one extra bit for noise
		NUM_TAPS = 4,
		SHIFT_COUNT_BITS = 4,
		MAX_LEFT_SHIFT = 2
	) (
		input wire clk, reset,

		input wire [IN_BITS-1:0] u, // input signal, sampled at pulse done
		input [SHIFT_COUNT_BITS-1:0] u_rshift,

		input wire dual_slope_en, double_slope_en,
		input wire [PWM_BITS-1:0] compare_max, // controls the PWM period, pulse_width should be <= compare_max (less if´one pulse/period is wanted)

		output wire pulse_done,
		output wire pwm_out,

		output wire [PWM_BITS-1:0] pulse_width_out,

		input wire force_err,
		input wire [FRAC_BITS-1:0] forced_err_value
	);

	wire y_valid;
	wire [PWM_BITS-1:0] y;
	reg [PWM_BITS-1:0] pulse_width;
	always_ff @(posedge clk) begin
		// Assumes that the period is long enough that y_valid becomes high before pulse_done
		if (pulse_done) pulse_width <= y;
	end

	delta_sigma_modulator #(.IN_BITS(IN_BITS), .FRAC_BITS(FRAC_BITS), .OUT_BITS(PWM_BITS), .NUM_TAPS(NUM_TAPS), .SHIFT_COUNT_BITS(SHIFT_COUNT_BITS), .MAX_LEFT_SHIFT(MAX_LEFT_SHIFT)) ds_mod(
		.clk(clk), .reset(reset), .en(!y_valid || pulse_done),
		.u(u), .u_rshift(u_rshift), .force_err(force_err), .forced_err_value(forced_err_value),
		.y(y), .y_valid_out(y_valid)
	);
	pulse_width_modulator #(.BITS(PWM_BITS)) pw_modulator(
		.clk(clk), .reset(reset),
		.dual_slope_en(dual_slope_en), .double_slope_en(double_slope_en), .compare_max(compare_max),
		.pulse_width(pulse_width),
		.pwm_out(pwm_out), .pulse_done(pulse_done)
	);

	assign pulse_width_out = pulse_width;
endmodule : delta_sigma_pw_modulator
