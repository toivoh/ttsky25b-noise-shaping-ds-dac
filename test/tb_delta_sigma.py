# SPDX-FileCopyrightText: © 2025 Toivo Henningsson
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles


@cocotb.test()
async def test_project(dut):
	clock = Clock(dut.clk, 10, units="us")
	cocotb.start_soon(clock.start())

	cycles_per_sample = 14


	# Forced err: test response to single error
	# -----------------------------------------
	dut.rst_n.value = 0
	await ClockCycles(dut.clk, 10)
	dut.rst_n.value = 1

	dut.coeff_choice.value = 3

	dut.u.value = 0
	dut.force_err.value = 1
	#dut.forced_err_value.value = -128
	dut.forced_err_value.value = 1

	await ClockCycles(dut.clk, cycles_per_sample) # should be enough to read err
	dut.forced_err_value.value = 0
	await ClockCycles(dut.clk, 5*cycles_per_sample)

	dut.force_err.value = 0


	# Test normal operation
	# ---------------------
	dut.rst_n.value = 0
	await ClockCycles(dut.clk, 10)
	dut.rst_n.value = 1

	dut.u.value = 64+128

	await ClockCycles(dut.clk, 32*cycles_per_sample)
