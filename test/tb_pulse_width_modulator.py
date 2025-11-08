# SPDX-FileCopyrightText: © 2025 Toivo Henningsson
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

PWM_BITS  = 11
PW_MASK = (1 << PWM_BITS) - 1

@cocotb.test()
async def test_project(dut):
	clock = Clock(dut.clk, 10, units="us")
	cocotb.start_soon(clock.start())

	for mode in range(3):
		dut.dual_slope_en.value = (mode >= 1);
		dut.double_slope_en.value = (mode == 2);

		dut.rst_n.value = 0
		await ClockCycles(dut.clk, 10)
		dut.rst_n.value = 1

		period = 4
		dut.compare_max.value = period-1

		for j in range(-1,period+2):
			pw = j
			if pw > period: pw = (3 << (PWM_BITS-2))-1
			dut.pulse_width.value = pw & PW_MASK
			for i in range(2*period):
				await ClockCycles(dut.clk, 1)
				if dut.pulse_done.value.integer != 0: break

