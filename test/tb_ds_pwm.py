# SPDX-FileCopyrightText: © 2025 Toivo Henningsson
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles


@cocotb.test()
async def test_project(dut):
	clock = Clock(dut.clk, 10, units="us")
	cocotb.start_soon(clock.start())


	dut.rst_n.value = 0
	await ClockCycles(dut.clk, 10)
	dut.rst_n.value = 1

	period = 6 # minimum period=5
	dut.compare_max.value = period-1

	dut.u.value = 64+128 + 256*2


	await ClockCycles(dut.clk, 32*period)
