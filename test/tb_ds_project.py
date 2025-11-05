# SPDX-FileCopyrightText: © 2025 Toivo Henningsson
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

FRAC_BITS = 16
PWM_BITS  = 8
IN_BITS = 23

MAX_U_RSHIFT = IN_BITS - 16
PW_MASK = (1 << PWM_BITS) - 1

class DeltaSigma:
	def __init__(self, FRAC_BITS, coeffs):
		self.FRAC_BITS = FRAC_BITS
		self.coeffs = coeffs
		self.n = len(coeffs)
		self.correction = 0
		self.errors = [0]*self.n

	def process(self, u):
		x = self.correction + u
		y = x >> self.FRAC_BITS
		x -= (1 << (self.FRAC_BITS-1))
		x -= y << self.FRAC_BITS
		error = x

#		print("x =", x)
#		print(self.errors)
		self.errors.pop(0)
#		print(self.errors)
		self.errors.append(x)
#		print(self.errors)

		correction = 0
		for (coeff, error) in zip(self.coeffs, self.errors):
			correction += coeff*error

		self.correction = correction

#		print("(u, e,corr,y) =", (u, self.errors, self.correction, y))

		return y

async def write_reg(dut, addr, value):
	# Assumes uio[4] was high
	dut.ui_in.value = value & 255
	dut.uio_in.value = ((addr&7)<<1)
	await ClockCycles(dut.clk, 3)
	dut.ui_in.value = value >> 8
	dut.uio_in.value = 16 | ((addr&7)<<1)
	await ClockCycles(dut.clk, 3)


async def test_delta_sigma(dut, u_rshift):
	dut.uio_in.value = 16
	dut.rst_n.value = 0
	await ClockCycles(dut.clk, 10)
	dut.rst_n.value = 1

	period = 7

	u_lshift = MAX_U_RSHIFT - u_rshift
	eff_frac_bits = FRAC_BITS - u_lshift
	frac_mask = (1 << eff_frac_bits) - 1
	int_mask = ((1 << 16) - 1) & ~frac_mask

	reg1_value = (period&255) | ((u_rshift&15) << 8)
	await write_reg(dut, 1, reg1_value | (1 << 13)) # turn on force_err to keep err at zero while  we change u_rshift and u
	await write_reg(dut, 0, 1 << (FRAC_BITS - 1 - u_lshift))
	await write_reg(dut, 1, reg1_value)
	await ClockCycles(dut.clk, 1)


#	ds = DeltaSigma(FRAC_BITS, [1, -4, 6, -4])
	ds = DeltaSigma(FRAC_BITS, [-1, 4, -6, 4])

	# Wait for the first toggle on pulse_toggle
	pt = dut.uio_out.value[0]
	for j in range(period*2): # should be a while loop, but make it a for loop so that we don't wait indefinitely
		if dut.uio_out.value[0] != pt: break
		await ClockCycles(dut.clk, 1)
	pt = not pt

#	print("pt = ", pt)
	for i in range(256):
#	for i in range(4):
		u = i*i
		# Alternate the integer bits between lowest and highest to test the range
		u &= frac_mask
		u |= (i&1) * int_mask
		#u = 0 if i == 0 else (1 << (FRAC_BITS-1))

#		print("u =", u)
		await write_reg(dut, 0, u)
		for j in range(period*2): # should be a while loop, but make it a for loop so that we don't wait indefinitely
			#print("pt = ", pt, " dut.uio_out.value[0] =", dut.uio_out.value[0])
			if dut.uio_out.value[0] != pt: break
			await ClockCycles(dut.clk, 1)
		pt = not pt

		y_expected = ds.process(u << u_lshift)
		y_expected &= PW_MASK
		y = dut.uo_out.value.integer

#		print((y_expected, y))
		assert y == y_expected


@cocotb.test()
async def test_project(dut):
	clock = Clock(dut.clk, 10, units="us")
	cocotb.start_soon(clock.start())

	# Try some register writes

	top = dut.user_project
	try:
		registers = top.registers
		rtl = True
	except:
		registers = None
		rtl = False

	dut.uio_in.value = 16
	dut.rst_n.value = 0
	await ClockCycles(dut.clk, 10)
	dut.rst_n.value = 1

	period = 7
	reg1_value = (1<<14) | period
	await write_reg(dut, 1, reg1_value)
	reg2_value = 0x1234
	await write_reg(dut, 2, reg2_value)

	if rtl: assert top.registers[1].value.integer == reg1_value
	await ClockCycles(dut.clk, 1)
	if rtl: assert top.registers[2].value.integer == reg2_value

	for u_rshift in range(MAX_U_RSHIFT+1):
		print("\nu_rshift =", u_rshift)
		await test_delta_sigma(dut, u_rshift)

