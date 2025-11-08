# SPDX-FileCopyrightText: © 2025 Toivo Henningsson
# SPDX-License-Identifier: Apache-2.0

from model import *
import numpy as np
from numpy.fft import fft
from matplotlib import pyplot as plt

#def __init__(self, noise_mode, n_decorrelate, coeffs):
ds = DeltaSigma(noise_mode=3, n_decorrelate=5, coeffs=[-1, 4, -6, 4])
#ds = DeltaSigma(noise_mode=3, n_decorrelate=5, coeffs=[1])

n_samples = 4096
amp = 64

ii = np.arange(n_samples)
u = (amp << FRAC_BITS)*np.sin(ii*2*np.pi/n_samples)
u = np.array(u, dtype=int)

y = []
for ui in u:
	y.append(ds.process(ui))
y = np.array(y)

f = abs(fft(y)[0:n_samples//2])
sin_amp = n_samples*amp/2
f[1] -= sin_amp
f /= sin_amp
#plt.plot(f[1:])
plt.plot(f[1:]**2)
plt.show()
