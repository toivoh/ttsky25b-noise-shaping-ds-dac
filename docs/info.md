<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

![block diagram](block-diagram.png)

The aim of this project is to test if it is possible to output 16 bit audio using a single digital output from a pure digital Tiny Tapeout design.
For this purpose, it implements a noise-shaping delta-sigma converter that feeds into a pulse width modulator to create the digital output signal.

The design can be driven with sample data (eg using the PIO functionality in the RP2040/RP2350 microcontroller on the demo board). There is also a built-in triangle wave generator for testing without needing to feed sample data.

### Operating principle

Assume that we want to output an audio signal at 48 kHz from a design that is clocked at 50 MHz, using single digital output pin fed by a flip-flop. That gives us about 1040 cycles to output each sample.
(This design can go up to 66.66 MHz, but the main target is to get a working output at 50 MHz).
If we output each sample by controlling the average over a 1040 cycle period, we get a little more than 10 bits of resolution. This can for instance be done with pulse width modulation (PWM).

One way to look at it is that we are taking the original unquantized output signal and adding noise to it so that it becomes a quantized signal with a resolution that can actually be output.
The target can be a one bit signal sampled at 50 MHz, or a signal with higher bit depth and lower frequency output using PWM for instance (we will aim for the latter). 
There is a least amount of noise we need to add to make the output signal quantized, but the noise doesn't have to be added equally across the frequency spectrum.
This design uses a noise shaping sigma-delta modulator to shape the quantization noise to put most of it above the audible frequency range.

#### Example
Let's use a 4th order filter (the highest order that seems to be useful with a clock frequency of 50 MHz in this setup).
We will consider two kinds of error:

* The _quantization error_ is the difference between the target output and the actual output
* The _quantization noise_ is the difference between the input signal and the actual output

(see the figure at the top.)
At each sample, we will make a quantization error.
Assume (for the purpose of illustration) that we make a quantization error of 1 in the first sample.
The 4th order filter will add corrections to the following samples 4 samples, with values `-4, 6, -4, 1`.
Taken together, the sequence of disturbances caused by the first quantization error of 1 becomes

	1, -4, 6, -4, 1

where the the first 1 comes from the quantization noise in the first sample, and the rest is corrections added by the filter.

This sequence is the impulse response of a filter `(1 - z^-1)^4` with 4 zeros at `z = 1` (zero frequency), and has very little low frequency content.
Adding the corrections will add more energy to the quantization noise (in this case, the variance will be 70x higher, `1^2+4^2+6^2+4^2+1^2 = 70`), but the low frequency components of the quantization noise will be greatly reduced by the corrections.

The corrections can not be applied exactly because there will be quantization errors in the following samples as well, but these errors can be corrected in the same way.
The quantization error is bounded, and the bound doesn't grow due to the corrections, so the corrections will be bounded as well.
If the quantizer rounds the output to the nearest integer, the magnitude of the quantization error is `<= 0.5`, and the 4th order filter adds noise of up to `+- 7.5` output steps to each sample.

The output of the delta-sigma modulator is fed to a pulse width modulator with programmable period. The PWM period sets the range of the output signal.
We have to make sure that the period is long enough to fit the variation of both the quantization noise and the input signal.
Setting the PWM period is a tradeoff between output resolution and range on one hand, and output frequency on the other:

* If the magnitude of the of the input signal becomes too low compared to the noise, the noise will dominate and the effective resolution will suffer.
* The longer we make the PWM period, the lower the filter's sampling frequency becomes, moving more of the high frequency quantization noise into the audible range.

In this case, a period of 47 cycles may be appropriate, to allow an output swing of 0-31 from the input signal combined with 0-14 (if we add 7.5) for the noise. 45 cycles would be enough for this purpose, but since rising and falling edges may propagate at different speeds throught the TT multiplexer, we also want to avoid hitting 0% or 100% duty cycle to keep one rising and one falling edge per pulse in the output signal.

#### Adding additional noise to the quantization error
The default behavior is to let the quantizer calculate the output by rounding the target output to the nearest integer.
This quantization produces the smallest quantization error, but the statistical properties may be unpredictable.
If the quantization error ends up including prominent frequency components (that might change with the input signal), it could create objectionable artifacts in some cases, if some of the quantization noise is audible.

The noise source (see the block diagram above) can be used to add extra noise to make the quantization error behave more like white noise.
Two noise modes are supported:

* Adding rectangular noise remove any correlation between quantization errors at different samples
	* The variance varies depending on the input value: from zero variance when hitting an integer to max variance in the middle between two integers (note that the `reg0 = u` has an offset so those to cases are actually switched)
	* The maximum quantization error becomes 1 (compared to 0.5 with noise source off).
* Adding triangular noise additionally removes noise modulation: The variance of the quantization error becomes independent of the input signal.
	* The maximum quantization error becomes 1.5.

Both of these cases assume that `n_decorrelate` is set high enough so that the noise source produces white noise.
The statistical properties of the quantization error are not well defined except when adding triangular noise, but if we assume the fractional part of the input signal to be uniformly distributed, then the quantization error has a variance of 1/12, 1/6, and 1/4 respectively for noise off/rectangular/triangular noise respectively.

### Interface

The design contains a number of 16 bit registers.
To write to one,

- Make sure that `data_part_in = 1`
- Set `data_in[7:0]` to the low byte
- Set `data_part_in = 0`
- Wait at least 3 cycles for the low byte to be buffered
- Set `data_in[7:0]` to the high byte
- Set `addr[2:0]` to the desired register address
- Set `data_part_in = 1`
- Wait 3 cycles for the register to be written

Registers:

| Register | Field            | Name              | Description            |
|---------:|:-----------------|:------------------|:-----------------------|
| 0        | `reg0[15:0]`     | `u`               | input signal           |
| 1        | `reg1[6:0]`      | `max_output`      | controls PWM period    |
|          | `reg1[10:8]`     | `u_rshift`        | input shift            |
|          | `reg1[12]`       | `ddr_en`          | enable DDR mode for PWM|
|          | `reg1[12]`       | `reset_lfsr`      | for testing            |
|          | `reg1[13]`       | `force_err_0`     | for testing            |
|          | `reg1[15:14]`    | `pwm_mode`        |                        |
| 2        | `reg2[3:2]`      | `filter_mode`     |                        |
|          | `reg2[11:8]`     | `n_decorrelate`   | noise decorrelation    |
|          | `reg2[15:14]`    | `noise_mode`      |                        |
| 3        | `reg3[12:0]`     | `delta_u`         | for triangle generator |

The actual 21-bit input signal has 7 integer bits and 14 fractional bits, and is formed as

	u_input = ((u << 5) >> u_rshift) - (1 << 13)

The range of output values supported by the pulse width modulator goes from 0 to `max_output`. Adjust the range of `u` and the size of `max_output` to accomodate the range of the input signal plus the quantization noise, while avoiding the need to actually use a pulse width of 0 or `max_output`.
Set `u_rshift` to get the desired range of the input signal. E g, if the input signal should be able to contribute a value of 0 to 31 to the output pulse width, set `u_rshift = 2` to effectively remove two integer bits from `u_inputs` and be able to control two more of the fractional bits.

The `filter_mode` field chooses between 4 filters:

| `filter_mode` | Filter order | Filter response |
|--------------:|-------------:|:----------------|
|             0 |            4 | `-4  6 -4 1`    |
|             1 |            3 | `-3  3 -1`      |
|             2 |            2 | `-2  1`         |
|             3 |            1 | `-1`            |

The filters have transfer functions `(1 - z^-1)^n_z - 1`, where `n_z = 4 - filter_mode`.
The maximum absolute value of the quantization noise will be the maximum absolute value of the quantization error times `2^n_z - 1`.
The 4th and maybe 3rd order filters are expected to be most useful.

The pulse width modulator supports 5 different modes, controlled by `pwm_mode` and `ddr_en`:

| `pwm_mode` | `ddr_en` | PWM mode              | PWM period              |
|-----------:|---------:|:----------------------|:------------------------|
|          0 |        0 | Non-phase-correct     | `max_output + 1`        |
|          1 |        0 | Phase-correct         | `2*(max_output + 1)`    |
|          3 |        0 | Semi-phase-correct    | `max_output + 1`        |
|          3 |        1 | Phase-correct DDR     | `max_output + 1`        |
|          2 |        1 | Non-phase-correct DDR | `(max_output + 1) >> 1` |

As the pulse width increases, the semi-phase-correct mode alternates expanding the pulse at the left and right side for every other step.
The non-phase-correct modes just expand the pulse from left to right, while the phase correct ones expand equally on both directions.

In the non-DDR modes, the output signal can only switch at rising clock edges, while it can switch at either clock edge in the DDR modes.
The non-DDR phase-correct mode creates the least amount of phase error, but since it doubles the PWM period, it looses one bit of output resolution (which could translate into losing several bits of effective output resolution).
Of the modes with PWM period `max_output + 1`, the non-phase correct mode is least accurate in centering the pulse (not at all) and the phase correct DDR mode is the most accurate. 

The non-phase correct DDR mode is a bonus mode that comes with some caveats regarding the actual pulse width that it outputs:

* The pulse width (in half cycles) is the output pulse width minus one (saturating at zero)
* The pulse width might not be correct when the output pulse width is >= `max_output`
* The pulse width increase from odd to even vs even to odd might not be the same, depending on the duty cycle of the input clock and the delay in the circuit

It is not expected to be a useful mode, but who knows?

The `noise_mode` field sets the noise mode:

| `noise_mode` | Noise mode  |
|-------------:|:------------|
|            0 | off         |
|            1 | rectangular |
|            3 | triangular  |

The noise source is based on a linear feedback shift register (LFSR), but to make it behave more like white noise, a number of decorrelation steps are applied, given by the `n_decorrelate` field. When the noise mode is off, `n_decorrelate` can be zero. When using noise, `n_decorrelate` should probably be >= 5.
Each decorrelation step adds two clock cycles to the delta sigma modulator computation, make sure that

	PWM period >= 15 + 2*n_decorrelate

or the computation will not have time to keep up with the PWM output, producing unexpected results.

The design contains a triangle wave generator that can be used to generate an input signal without driving `u` values from the outside in real time.
If `delta_u != 0`, `reg0 = u` is updated after each PWM pulse. `delta_u` is added to `u` once per PWM pulse until it would become >= 0xc000, then it is subtracted once per PWM pulse until `u` would become < 0x4000, and the pattern repeats. (`u` stays at the same value for one step when changing direction)
The triangle wave is centered in the middle of the range to make it possible to avoid clipping into zero/negative pulse widths, since saturating the pulse width will cause the noise shaping to fail.

### Other pins
The design has a few additional pins except those used by the register interface:

* `dac_out` is the actual output signal.
* `sample_toggle_out` toggles each time `pulse_divider+1` PWM pulses have been output. This can be used to time transfers of new input signal values `u`.
* `echo_out` echoes the value of `echo_in`. This could be used to test how a signal that is routed next to `dac_out` in the TT chip influences the noise performance. (`dac_out` is routed through the TT mux between `echo_out` and `uio_oe[0]`, where the latter is tied to 1) Otherwise, keep `echo_in` at a fixed value.
* `uo[7:0] = pulse_width` contains the pulse width calculated for the current pulse. Values between 128 and 191 will be output as a high signal on `dac_out` (saturate high), and values between 192 and 255 as a low signal (saturate low).

## Choosing parameters

First, assume that you have chosen values for `filter_mode`, `noise_mode`, `{ddr_en, pwm_mode}`, and `u_rshift`.
It remains to choose the range to use for `u` and the value of `max_output`, and to evaluate the output gain and effective resolution.

You probably want to limit `u` so that `output >= 1`. More generally, to achieve `y_min <= output <= y_max`, `u` should be limited according to

	u >= 2^(9 + u_rshift) * (y_min + 2^n_z * error_amp - 0.5)
	u <  2^(9 + u_rshift) * (y_max - 2^n_z * error_amp + 1.5)

where

	error_amp = 0.5 for noise source off
				1.0 for rectangular noise
				1.5 for triangular noise

If using the built-in triangle wave generator, `0x4000 <= u < 0xc000`, and you have to check if the parameters result in a lower bound of `u` that is below `0x4000`.

If you have an upper bound `u <= u_max`, then

	y <= y_max = floor((u_in + 2^n_z * error_amp - 0.5)/2^14)
	y <= y_max = floor(u_max/2^(9 + u_rshift) + 2^n_z * error_amp - 0.5)

Once `y_max` is known, choose `max_output = y_max+1` (or greater, but there should be no need for that) to ensure that the output never reaches 100% duty cycle.

## How to test

## External hardware

This project needs some way to use the `dac_out` output signal, and preferably to low pass filter it to filter out the high frequency noise.
Mike's audio Pmod (https://github.com/MichaelBell/tt-audio-pmod) can be used to convert the output to an audio signal for listening and includes a low pass filter to reduce frequencies above the audible range. Connect it to the `uio` Pmod.
