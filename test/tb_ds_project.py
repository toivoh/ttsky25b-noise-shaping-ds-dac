# SPDX-FileCopyrightText: © 2025 Toivo Henningsson
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

SHORT_TEST = False
#SHORT_TEST = True  # !!!!

FRAC_BITS = 16
PWM_BITS  = 8
IN_BITS = 23
LFSR_BITS = 22

MIN_PERIOD = 14

ONE_HALF = 1 << (FRAC_BITS - 1)
MAX_U_RSHIFT = IN_BITS - 16
PW_MASK = (1 << PWM_BITS) - 1
LFSR_BITS_HALF = LFSR_BITS >> 1
LFSR_MASK = (1 << LFSR_BITS) - 1
LFSR_MASK_M1 = (1 << (LFSR_BITS-1)) - 1
LFSR_MASK_LOW = (1 << LFSR_BITS_HALF) - 1

bit_permutation = [21, 17, 12, 19, 13, 20, 15, 11, 16, 14, 18, 7, 2, 4, 9, 6, 8, 1, 10, 3, 5, 0]

def bit_shuffle(p, x):
	y = 0
	for (i, j) in enumerate(p):
		y |= ((x>>j)&1)<<i
	return y

def decorrelate(x, n):
	for i in range(n):
		x = bit_shuffle(bit_permutation, x)
		x = (x + ((x & LFSR_MASK_LOW) << LFSR_BITS_HALF))
	return x & LFSR_MASK

def sext(x, nbits):
	x += (1 << (nbits-1))
	x &= (1 << nbits) - 1
	x -= (1 << (nbits-1))
	return x

class DeltaSigma:
	def __init__(self, noise_mode, n_decorrelate, coeffs):
		self.noise_mode = noise_mode
		self.n_decorrelate = n_decorrelate
		self.coeffs = coeffs
		self.n = len(coeffs)
		self.correction = 0
		self.errors = [0]*self.n
		self.lfsr_state = 0

	def process(self, u):
		# update LFSR
		lfsr_bit = 1 & ((self.lfsr_state >> (LFSR_BITS-1)) ^ ((self.lfsr_state >> (LFSR_BITS-2)) | ((self.lfsr_state & LFSR_MASK_M1) == 0) ))
		self.lfsr_state = ((self.lfsr_state << 1) & LFSR_MASK) | lfsr_bit

		noise = decorrelate(self.lfsr_state, self.n_decorrelate)
#		print("model: lfsr_state =", hex(self.lfsr_state), ", noise =", hex(noise))

		quant_noise1 = sext(noise >> (LFSR_BITS-FRAC_BITS), FRAC_BITS)
		noise2 = bit_shuffle(bit_permutation, noise)
		quant_noise2 = sext(noise2 >> (LFSR_BITS-FRAC_BITS), FRAC_BITS)

		if self.noise_mode == 0: quant_noise = 0
		elif self.noise_mode == 1: quant_noise = quant_noise1 # rectangle noise
		elif self.noise_mode == 3: quant_noise = quant_noise1 - quant_noise2 # triangle noise
		else: raise Error("invalid noise mode")

#		print("quant_noise =", hex(quant_noise))

		x = self.correction + u
		target = x - ONE_HALF

		y = (target + ONE_HALF + quant_noise) >> FRAC_BITS
		error = target - (y << FRAC_BITS)


#		x_pn = x + quant_noise
#		assert x_pn >> FRAC_BITS == y
#		err1 = x_pn & ((1 << FRAC_BITS)-1)
#		err1 -= (1 << (FRAC_BITS-1))



#		print("correction =", hex(self.correction))
#		print("u =", hex(u))
#		print("target =", hex(target))
#		print("x =", hex(x))
#		print("y =", hex(y))
#		print("error =", hex(error))
#
#		print()
#		print("x_pn =", hex(x_pn))
#		print("err1 =", hex(err1))
#		print()

#		print("x =", x)
#		print(self.errors)
		self.errors.pop(0)
#		print(self.errors)
		self.errors.append(error)
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


async def test_delta_sigma(dut, u_rshift, noise_mode, n_decorrelate, coeff_choice):
	dut.uio_in.value = 16
	dut.rst_n.value = 0
	await ClockCycles(dut.clk, 10)
	dut.rst_n.value = 1

	period = MIN_PERIOD + 2*n_decorrelate

	u_lshift = MAX_U_RSHIFT - u_rshift
	eff_frac_bits = FRAC_BITS - u_lshift
	frac_mask = (1 << eff_frac_bits) - 1
	int_mask = ((1 << 16) - 1) & ~frac_mask

	await write_reg(dut, 2, ((noise_mode&3) << 14) | ((n_decorrelate&15)<<8) | ((coeff_choice&63)<<2))
	reg1_value = (period&255) | ((u_rshift&15) << 8)
	await write_reg(dut, 1, reg1_value | (1 << 13)) # turn on force_err to keep err at zero while  we change u_rshift and u
	await write_reg(dut, 0, 1 << (FRAC_BITS - 1 - u_lshift))
	await write_reg(dut, 1, reg1_value | (1 << 12)) # turn on reset_lfsr (turns off after one pulse)
	await ClockCycles(dut.clk, 1)


	if coeff_choice == 0:   coeffs = [-1, 4, -6, 4]
	elif coeff_choice == 1: coeffs = [ 1, -3, 3]
	elif coeff_choice == 2: coeffs = [-1, 2]
	elif coeff_choice == 3: coeffs = [1]
	else: raise Error("Unsupported coeff_choice")


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
	for i in range(4 if SHORT_TEST else 256):
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

	period = MIN_PERIOD
	reg1_value = (1<<14) | period
	await write_reg(dut, 1, reg1_value)
	reg2_value = 0x1234
	await write_reg(dut, 2, reg2_value)

	if rtl: assert top.registers[1].value.integer == reg1_value
	await ClockCycles(dut.clk, 1)
	if rtl: assert top.registers[2].value.integer == reg2_value

	for (noise_mode, n_decorrelate, coeff_choice) in [(3,5,3), (3,5,2), (3,5,1), (0,0,0), (1,0,0), (1,5,0), (3,5,0), (3,15,0)]:
	#for (noise_mode, n_decorrelate, coeff_choice) in [(3,5,1), (0,0,0), (1,0,0), (1,5,0), (3,5,0), (3,15,0)]:
		print("\nnoise_mode = ", noise_mode, ", n_decorrelate = ", n_decorrelate, ", coeff_choice = ", coeff_choice, sep="")
		for u_rshift in [0] if SHORT_TEST else range(MAX_U_RSHIFT+1):
			print("\nu_rshift =", u_rshift)
			await test_delta_sigma(dut, u_rshift, noise_mode, n_decorrelate, coeff_choice)

