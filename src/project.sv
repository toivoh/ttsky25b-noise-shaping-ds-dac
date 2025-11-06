/*
 * Copyright (c) 2025 Toivo Henningsson
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_toivoh_delta_sigma #(
		parameter IN_BITS = 23,
		FRAC_BITS = 16,
		PWM_BITS = 8, // should include one extra bit for noise
		SHIFT_COUNT_BITS = 4,
		NUM_TAPS = 4
	)(
		input  wire [7:0] ui_in,    // Dedicated inputs
		output wire [7:0] uo_out,   // Dedicated outputs
		input  wire [7:0] uio_in,   // IOs: Input path
		output wire [7:0] uio_out,  // IOs: Output path
		output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
		input  wire       ena,      // always 1 when the design is powered, so you can ignore it
		input  wire       clk,      // clock
		input  wire       rst_n     // reset_n - low to reset
	);

	wire reset = !rst_n;


	localparam ADDR_BITS = 3;
	localparam NUM_REGS = 3;


	(* mem2reg *) reg [15:0] registers[NUM_REGS];


	wire [7:0] data_in = ui_in;

	wire [ADDR_BITS-1:0] addr = uio_in[1+ADDR_BITS-1 -: ADDR_BITS];
	wire data_part_in = uio_in[4];
	wire echo_in = uio_in[5];

	// Synchronizer and FF to keep last value
	// --------------------------------------
	reg [2:0] data_part_sreg;
	always_ff @(posedge clk) begin
		if (reset) data_part_sreg <= '1;
		else data_part_sreg <= {data_part_in, data_part_sreg[2:1]};
	end
	wire data_part = data_part_sreg[1];
	wire last_data_part = data_part_sreg[0];

	// Register input
	// --------------
	reg [7:0] data_low;
	always_ff @(posedge clk) if (data_part == 0 && last_data_part == 1) data_low <= data_in;

	wire [15:0] data16_in = {data_in, data_low};

	wire data16_we = (data_part == 1 && last_data_part == 0);

	always_ff @(posedge clk) begin
		if (reset) begin
			registers[0] <= 1 << (FRAC_BITS - 1);
			registers[1] <= (IN_BITS-16) << 8;
			registers[2] <= '0;
			// TODO: more registers?
		end else begin
			if (data16_we && addr == 0) registers[0] <= data16_in;
			if (data16_we && addr == 1) registers[1] <= data16_in;
			if (data16_we && addr == 2) registers[2] <= data16_in;
			// TODO: more registers?
		end
	end

	wire [IN_BITS-1:0] u = {registers[0], {(IN_BITS-16){1'b0}}};
	wire force_err = registers[1][13];
	wire dual_slope_en = registers[1][14];
	wire double_slope_en = registers[1][15];
	wire [PWM_BITS-1:0] compare_max = registers[1][PWM_BITS-1:0];
	wire [SHIFT_COUNT_BITS-1:0] u_rshift = registers[1][8+SHIFT_COUNT_BITS-1 -: SHIFT_COUNT_BITS];

	wire pulse_done, pwm_out;
	wire [PWM_BITS-1:0] pulse_width;
	delta_sigma_pw_modulator #(.IN_BITS(IN_BITS), .FRAC_BITS(FRAC_BITS), .PWM_BITS(PWM_BITS), .NUM_TAPS(NUM_TAPS)) modulator(
		.clk(clk), .reset(reset),
		.u(u), .u_rshift(u_rshift),
		.dual_slope_en(dual_slope_en), .double_slope_en(double_slope_en), .compare_max(compare_max),
		.pulse_done(pulse_done), .pwm_out(pwm_out), .pulse_width_out(pulse_width),
		.force_err(force_err), .forced_err_value('0)
	);

	reg pulse_toggle;
	reg [7:0] pulse_counter;
	always_ff @(posedge clk) begin
		if (reset) begin
			pulse_toggle <= 0;
			pulse_counter <= 0;
		end else begin
			if (pulse_done) begin
				if (pulse_counter == 0) begin
					pulse_toggle <= !pulse_toggle;
					pulse_counter <= registers[2];
				end else begin
					pulse_counter <= pulse_counter - 1;
				end
			end
		end
	end

	reg pwm_reg;
	always_ff @(posedge clk) pwm_reg <= pwm_out;

	// not registers
	reg [7:0] uio_out_r, uio_oe_r;
	always_comb begin
		uio_out_r = '0; uio_oe_r = '0;

		uio_oe_r[7] = 1'b1; uio_out_r[7] = pwm_reg;
		uio_oe_r[6] = 1'b1; uio_out_r[6] = echo_in;
		uio_oe_r[0] = 1'b1; uio_out_r[0] = pulse_toggle;
	end
	assign uio_out = uio_out_r;
	assign uio_oe = uio_oe_r;
	assign uo_out = pulse_width;
endmodule : tt_um_toivoh_delta_sigma
