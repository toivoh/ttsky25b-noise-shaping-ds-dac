# SPDX-FileCopyrightText: © 2025 Toivo Henningsson
# SPDX-License-Identifier: Apache-2.0

FRAC_BITS = 14
PWM_BITS  = 8
IN_BITS = 21
LFSR_BITS = 22

MIN_PERIOD = 15

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
		else: raise Exception("invalid noise mode")

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
