# SPDX-FileCopyrightText: © 2025 Toivo Henningsson
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

from model import *

SHORT_TEST = False
#SHORT_TEST = True  # !!!!

async def write_reg(dut, addr, value):
	# Assumes uio[4] was high
	dut.ui_in.value = value & 255
	dut.uio_in.value = ((addr&7)<<1)
	await ClockCycles(dut.clk, 3)
	dut.ui_in.value = value >> 8
	dut.uio_in.value = 16 | ((addr&7)<<1)
	await ClockCycles(dut.clk, 3)


async def test_delta_sigma(dut, u_rshift, noise_mode, n_decorrelate, coeff_choice, period=-1, cover_int_range=False, pwm_mode=0):
	dut.uio_in.value = 16
	dut.rst_n.value = 0
	await ClockCycles(dut.clk, 10)
	dut.rst_n.value = 1

	period = max(period, MIN_PERIOD + 2*n_decorrelate)

	u_lshift = MAX_U_RSHIFT - u_rshift
	eff_frac_bits = FRAC_BITS - u_lshift
	frac_mask = (1 << eff_frac_bits) - 1
	int_mask = ((1 << 16) - 1) & ~frac_mask

	await write_reg(dut, 2, ((noise_mode&3) << 14) | ((n_decorrelate&15)<<8) | ((coeff_choice&63)<<2))
	reg1_value = ((period-1)&255) | ((u_rshift&15) << 8) | ((pwm_mode&3)<<14)
	await write_reg(dut, 1, reg1_value | (1 << 13)) # turn on force_err to keep err at zero while  we change u_rshift and u
	await write_reg(dut, 0, 1 << (FRAC_BITS - 1 - u_lshift))
	await write_reg(dut, 1, reg1_value | (1 << 12)) # turn on reset_lfsr (turns off after one pulse)
	await ClockCycles(dut.clk, 1)


	if coeff_choice == 0:   coeffs = [-1, 4, -6, 4]
	elif coeff_choice == 1: coeffs = [ 1, -3, 3]
	elif coeff_choice == 2: coeffs = [-1, 2]
	elif coeff_choice == 3: coeffs = [1]
	else: raise Exception("Unsupported coeff_choice")


#	ds = DeltaSigma(noise_mode, n_decorrelate, [1, -4, 6, -4])
	ds = DeltaSigma(noise_mode, n_decorrelate, coeffs)

	# Wait for the first toggle on pulse_toggle
	pt = dut.uio_out.value[0]
	for j in range(period*2): # should be a while loop, but make it a for loop so that we don't wait indefinitely
		if dut.uio_out.value[0] != pt: break
		await ClockCycles(dut.clk, 1)
	pt = not pt

#	print("pt = ", pt)
#	for i in range(256):
#	for i in range(4):
	next_pw_expected = -1
	for i in range(4 if SHORT_TEST else 256):
		u = i*i

		if cover_int_range:
			# Try to sweep through the range of integer bit values
			u &= frac_mask
			u |= (i<<8) & int_mask
		else:
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

		y_expected0 = ds.process(u << u_lshift)
		y_expected = y_expected0 & PW_MASK
		y = dut.uo_out.value.integer

#		print((y_expected, y))
		assert y == y_expected

		await ClockCycles(dut.clk, 1) # Wait one additional cycle after pulse_toggle toggled before reading out pulse_width_measured
		pulse_width_measured = dut.pulse_width_measured.value

		#print("next_pw_expected =", next_pw_expected)
		#print("pulse_width_measured =", pulse_width_measured)
		#print("y_expected0 =", y_expected0)

		if next_pw_expected >= 0: assert pulse_width_measured == next_pw_expected

		next_pw_expected = max(0, min(period, y_expected0))


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

	period = MIN_PERIOD
	reg1_value = (1<<14) | period
	await write_reg(dut, 1, reg1_value)
	reg2_value = 0x1234
	await write_reg(dut, 2, reg2_value)

	if rtl: assert top.registers[1].value.integer == reg1_value
	await ClockCycles(dut.clk, 1)
	if rtl: assert top.registers[2].value.integer == reg2_value

	for (noise_mode, n_decorrelate, coeff_choice) in [(3,5,3), (3,5,2), (3,5,1), (0,0,0), (1,0,0), (1,5,0), (3,5,0), (3,15,0)]:
	#for (noise_mode, n_decorrelate, coeff_choice) in [(0,0,0), (1,0,0), (1,5,0), (3,5,0), (3,15,0), (3,5,3), (3,5,2), (3,5,1)]:
	#for (noise_mode, n_decorrelate, coeff_choice) in [(3,5,1), (0,0,0), (1,0,0), (1,5,0), (3,5,0), (3,15,0)]:
		print("\nnoise_mode = ", noise_mode, ", n_decorrelate = ", n_decorrelate, ", coeff_choice = ", coeff_choice, sep="")
		for u_rshift in [0] if SHORT_TEST else range(MAX_U_RSHIFT+1):
			print("\nu_rshift =", u_rshift)
			await test_delta_sigma(dut, u_rshift, noise_mode, n_decorrelate, coeff_choice)

	# Test pulse width over the whole range
	await test_delta_sigma(dut, u_rshift=0, noise_mode=3, n_decorrelate=0, coeff_choice=0, period=128, cover_int_range=True, pwm_mode=0)
	await test_delta_sigma(dut, u_rshift=0, noise_mode=3, n_decorrelate=0, coeff_choice=0, period=128, cover_int_range=True, pwm_mode=3)
