# SPDX-FileCopyrightText: © 2025 Toivo Henningsson
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

from model import *

async def write_reg(dut, addr, value):
	# Assumes uio[4] was high
	dut.ui_in.value = value & 255
	dut.uio_in.value = ((addr&7)<<1)
	await ClockCycles(dut.clk, 3)
	dut.ui_in.value = value >> 8
	dut.uio_in.value = 16 | ((addr&7)<<1)
	await ClockCycles(dut.clk, 3)

@cocotb.test()
async def test_project(dut):
	clock = Clock(dut.clk, 10, units="us")
	cocotb.start_soon(clock.start())

	top = dut.user_project

	dut.uio_in.value = 16
	dut.rst_n.value = 0
	await ClockCycles(dut.clk, 10)
	dut.rst_n.value = 1

	period = MIN_PERIOD
	reg1_value = period-1
	await write_reg(dut, 1, reg1_value)

	for i in range(16):
		await write_reg(dut, 3, i << 4)
		await ClockCycles(dut.clk, 256*period)
