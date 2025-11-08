`default_nettype none
`timescale 1ns / 1ps

/* This testbench just instantiates the module and makes some convenient wires
   that can be driven / tested by the cocotb test.py.
*/
module tb_ds_project();

	// Dump the signals to a VCD file. You can view it with gtkwave or surfer.
	initial begin
		$dumpfile("tb_ds_project.vcd");
		$dumpvars(0, tb_ds_project);
		#1;
	end

	// Wire up the inputs and outputs:
	reg clk;
	reg rst_n;
	reg ena;
	reg [7:0] ui_in;
	reg [7:0] uio_in;
	wire [7:0] uo_out;
	wire [7:0] uio_out;
	wire [7:0] uio_oe;
	`ifdef GL_TEST
	wire VPWR = 1'b1;
	wire VGND = 1'b0;
	`endif

	tt_um_toivoh_delta_sigma user_project (

		// Include power ports for the Gate Level test:
`ifdef GL_TEST
		.VPWR(VPWR),
		.VGND(VGND),
`endif

		.ui_in  (ui_in),    // Dedicated inputs
		.uo_out (uo_out),   // Dedicated outputs
		.uio_in (uio_in),   // IOs: Input path
		.uio_out(uio_out),  // IOs: Output path
		.uio_oe (uio_oe),   // IOs: Enable path (active high: 0=input, 1=output)
		.ena    (ena),      // enable - goes high when design is selected
		.clk    (clk),      // clock
		.rst_n  (rst_n)     // not reset
	);

	wire pulse_toggle = uio_out[0];
	wire pwm_out = uio_out[7];
	reg last_pulse_toggle, pulse_toggled;
	int pulse_width_measured;
	always_ff @(posedge clk) begin
		if (!rst_n) begin
			pulse_toggled = 0;
			pulse_width_measured = 0;
		end else begin
			pulse_width_measured <= (pulse_toggled ? 0 : pulse_width_measured) + pwm_out;
		end
		pulse_toggled <= (pulse_toggle != last_pulse_toggle);
		last_pulse_toggle <= pulse_toggle;
	end


`ifndef GL_TEST
	wire [15:0] reg0 = user_project.registers[0];
	wire [15:0] reg1 = user_project.registers[1];
	wire [15:0] reg2 = user_project.registers[2];

	localparam SREG_BITS = 18;

	wire [SREG_BITS-1:0] sreg0 = user_project.modulator.ds_mod.sreg[0];
	wire [SREG_BITS-1:0] sreg1 = user_project.modulator.ds_mod.sreg[1];
	wire [SREG_BITS-1:0] sreg2 = user_project.modulator.ds_mod.sreg[2];

	localparam LFSR_BITS = 22;

	reg [LFSR_BITS-1:0] lfsr_state_sampled;
	always_ff @(posedge clk) if (user_project.modulator.ds_mod.do_step_lfsr) lfsr_state_sampled <= user_project.modulator.ds_mod.next_lfsr_state;

`endif
endmodule
