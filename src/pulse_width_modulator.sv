/*
 * Copyright (c) 2025 Toivo Henningsson
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module pulse_width_modulator #(
		parameter BITS=11
	) (
		input wire clk, reset,

		input wire dual_slope_en, double_slope_en,
		input wire [BITS-1:0] compare_max, // controls the PWM period, pulse_width should be <= compare_max (less if´one pulse/period is wanted)

		input wire [BITS-1:0] pulse_width, // range is -1/4*2^BITS <= pulse_width < 3/4*2^BITS
		output wire pulse_done, // when high, supply the next pulse_width value in the next cycle
		output wire pwm_out
	);

	reg direction;
	reg [BITS-1:0] compare_value;

	//wire compare_value_at_max = (compare_value == compare_max);
	// To avoid taking a very long period when changing compare value. We could reset the compare value instead when changing compare_max?
	wire compare_value_at_max = compare_value >= compare_max;

	// not registers
	reg r_pulse_done;
	reg signed [2:0] delta;
	reg next_direction;
	always_comb begin
		if (dual_slope_en) begin
			delta = direction ? 1 : -1;
			if (double_slope_en) delta = direction ? 2 : -2;

			next_direction = direction;
			if (compare_value_at_max && (direction == 1)) begin
				delta = double_slope_en ? -1 : 0;
				next_direction = 0;
			end

			r_pulse_done = (direction == 0) & (compare_value == 0); // compare_value == 1 ?
		end else begin
			delta = 1;
			next_direction = 1;

			r_pulse_done = compare_value_at_max;
		end
	end
	assign pulse_done = r_pulse_done;

	always_ff @(posedge clk) begin
		if (reset) begin
			direction <= 1;
			compare_value <= double_slope_en;
		end else begin
			if (pulse_done) compare_value <= double_slope_en;
			else compare_value <= $signed(compare_value) + $signed(delta);

			direction <= pulse_done ? 1 : next_direction;
		end
	end

	// TODO: Hold the pulse together? Now it's the low pulse that is continuous -- shouldn't make a difference though
	assign pwm_out = pulse_width[BITS-1] ? !pulse_width[BITS-2] : (compare_value < pulse_width);
endmodule : pulse_width_modulator
