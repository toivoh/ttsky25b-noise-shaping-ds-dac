/*
 * Copyright (c) 2025 Toivo Henningsson
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_toivoh_delta_sigma #(
		parameter IN_BITS = 21,
		FRAC_BITS = 14,
		PWM_BITS = 8, // should include one extra bit for noise
		SHIFT_COUNT_BITS = 3,
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
	localparam NUM_REGS = 4;


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

	// Triangle wave generator
	// -----------------------

	wire [15:0] u16_sum;
	wire u16_sum_valid;

	reg u_direction; // 0 = up (don't invert delta_u16)

	wire [15:0] u16 = registers[0];

/*
	localparam OCTAVE_BITS = 4;
	wire [2:0] note = registers[3][4:0];
	wire [OCTAVE_BITS-1:0] octave = registers[3][8:5];

	//wire [14:0] delta_u16_0 = 15'b101010101010101;
	reg [14:0] delta_u16_0;
	always_comb begin
#		case (note)
#			0: delta_u16_0 = 15'b100000000000000;
#			1: delta_u16_0 = 15'b110000000000000;
#			2: delta_u16_0 = 15'b101000000000000;
#			3: delta_u16_0 = 15'b100100000000000;
#			4: delta_u16_0 = 15'b111100000000000;
#			5: delta_u16_0 = 15'b110110000000000;
#			6: delta_u16_0 = 15'b101101000000000;
#			7: delta_u16_0 = 15'b101010101010101;
#			default: delta_u16_0 = 'X;
#		endcase
		delta_u16_0 = (1 << 14) | note << (14-5);
		if (note == 'b0101) delta_u16_0[10:0] = 10'b0101010101;
	end

	wire [15:0] delta_u16 = delta_u16_0 >> ~octave;
	//wire [15:0] u16_sum = u16 + (u_direction ? ~delta_u16 : delta_u16) + u_direction;
*/

	wire [15:0] delta_u16 = registers[3][14:0];

	reg next_u_direction;
	reg update_u;
	always_comb begin
		update_u = 0;
		next_u_direction = u_direction;

		if (u16_sum_valid) begin
			update_u = 1;
			if (u_direction == 0) begin
				if (u16_sum[15:14] == '1) begin
					update_u = 0; next_u_direction = 1;
				end
			end else begin
				if (u16_sum[15:14] == '0) begin
					update_u = 0; next_u_direction = 0;
				end
			end
		end
	end

	// Register input
	// --------------
	reg [7:0] data_low;
	always_ff @(posedge clk) if (data_part == 0 && last_data_part == 1) data_low <= data_in;

	wire [15:0] data16_in = {data_in, data_low};

	wire data16_we = (data_part == 1 && last_data_part == 0);

	wire pulse_done, pwm_out;
	wire [PWM_BITS-1:0] pulse_width;

	always_ff @(posedge clk) begin
		if (reset) begin
			registers[0] <= 1 << (FRAC_BITS - 1);
			registers[1] <= (IN_BITS-16) << 8;
			registers[2] <= '0;
			registers[3] <= '0;
			// TODO: more registers?
			u_direction <= 0;
		end else begin
			if (pulse_done) registers[1][12] <= 0; // TODO: better reset condition?
			if (update_u) registers[0] <= u16_sum;

			if (data16_we && addr == 0) registers[0] <= data16_in;
			if (data16_we && addr == 1) registers[1] <= data16_in;
			if (data16_we && addr == 2) registers[2] <= data16_in;
			if (data16_we && addr == 3) registers[3] <= data16_in;
			// TODO: more registers?
			u_direction <= next_u_direction;
		end
	end

	wire [IN_BITS-1:0] u = {registers[0], {(IN_BITS-16){1'b0}}};
	wire [SHIFT_COUNT_BITS-1:0] u_rshift = registers[1][8+SHIFT_COUNT_BITS-1 -: SHIFT_COUNT_BITS];
	wire ddr_en = registers[1][11];
	wire reset_lfsr = registers[1][12];
	wire force_err = registers[1][13];
	wire dual_slope_en = registers[1][14];
	wire double_slope_en = registers[1][15];
	//wire [PWM_BITS-1:0] compare_max = registers[1][PWM_BITS-1:0];
	wire [PWM_BITS-1:0] compare_max = registers[1][PWM_BITS-1-1:0]; // The top PWM bit is for saturation, don't need it for compare_max

	//localparam PULSE_COUNTER_BITS = 6;

	//wire [PULSE_COUNTER_BITS-1:0] pulse_divider = registers[2][PULSE_COUNTER_BITS-1:0];
	wire [5:0] coeff_choice = registers[2][7:2];
	wire [3:0] n_decorrelate = registers[2][11:8];
	wire [1:0] noise_mode = registers[2][15:14];

	delta_sigma_pw_modulator #(.IN_BITS(IN_BITS), .FRAC_BITS(FRAC_BITS), .PWM_BITS(PWM_BITS), .NUM_TAPS(NUM_TAPS)) modulator(
		.clk(clk), .reset(reset), .reset_lfsr(reset_lfsr),
		.u(u), .u_rshift(u_rshift), .noise_mode(noise_mode), .n_decorrelate(n_decorrelate), .coeff_choice(coeff_choice),
		.dual_slope_en(dual_slope_en), .double_slope_en(double_slope_en), .ddr_en(ddr_en), .compare_max(compare_max),
		.pulse_done(pulse_done), .pwm_out(pwm_out), .pulse_width_out(pulse_width),
		.force_err(force_err), .forced_err_value('0),
		.alt_src1(delta_u16), .alt_inv_src1(u_direction), .result_out(u16_sum), .result_out_valid(u16_sum_valid)
	);

	reg pulse_toggle;
	//reg [7:0] pulse_counter;
	always_ff @(posedge clk) begin
		if (reset) begin
			pulse_toggle <= 0;
			//pulse_counter <= 0;
		end else begin
			if (pulse_done) begin
				/*
				if (pulse_counter == 0) begin
					pulse_toggle <= !pulse_toggle;
					pulse_counter <= pulse_divider;
				end else begin
					pulse_counter <= pulse_counter - 1;
				end
				*/
				pulse_toggle <= !pulse_toggle;
			end
		end
	end

	// not registers
	reg [7:0] uio_out_r, uio_oe_r;
	always_comb begin
		uio_out_r = '0; uio_oe_r = '0;

		uio_oe_r[7] = 1'b1; uio_out_r[7] = pwm_out;
		uio_oe_r[6] = 1'b1; uio_out_r[6] = echo_in;
		uio_oe_r[0] = 1'b1; uio_out_r[0] = pulse_toggle;
	end
	assign uio_out = uio_out_r;
	assign uio_oe = uio_oe_r;
	assign uo_out = pulse_width;
endmodule : tt_um_toivoh_delta_sigma
