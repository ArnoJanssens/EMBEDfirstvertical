import numpy as np
import matplotlib.pyplot as plt
import sounddevice as sd
from matplotlib.animation import FuncAnimation

# ============================================================
# CONFIGURATION
# ============================================================

FS = 48000
N = 1024

METHOD = "max"  # "max", "rms", "energy"

FREQ_EDGES = np.array([
    1, 125, 250, 500, 1000,
    2000, 4000, 8000, 24000
])

GAIN = 10.0
SMOOTHING = 0.7

# ============================================================
# FFT FUNCTIONS
# ============================================================

def is_radix_2(n):
    return n > 0 and (n & (n - 1)) == 0


def fft_recursive(x):
    """Recursive radix-2 FFT, useful for comparison."""

    N = len(x)

    if not is_radix_2(N):
        raise ValueError("FFT size must be a power of 2")

    if N == 1:
        return np.array(x, dtype=complex)

    even = fft_recursive(x[::2])
    odd = fft_recursive(x[1::2])

    X = np.zeros(N, dtype=complex)

    for k in range(N // 2):
        W = np.exp(-2j * np.pi * k / N)
        T = W * odd[k]

        X[k] = even[k] + T
        X[k + N // 2] = even[k] - T

    return X


def prepare_fft(N):
    """Precompute bit-reversed indices and twiddle factors."""

    if not is_radix_2(N):
        raise ValueError("FFT size must be a power of 2")

    stages = N.bit_length() - 1

    # Bit-reversed input indices
    indices = [
        int(f"{i:0{stages}b}"[::-1], 2)
        for i in range(N)
    ]

    # Twiddle factors for each stage
    twiddles = []

    for stage in range(stages):
        group_size = 2 ** (stage + 1)

        W = np.exp(
            -2j * np.pi
            * np.arange(group_size // 2)
            / group_size
        )

        twiddles.append(W)

    return np.array(indices), twiddles


def fft_iterative(x, indices, twiddles):
    """
    Iterative radix-2 Decimation-in-Time FFT.
    This is the algorithm intended for FPGA implementation.
    """

    N = len(x)

    if not is_radix_2(N):
        raise ValueError("FFT size must be a power of 2")

    stages = N.bit_length() - 1

    # Bit-reverse input order
    X = np.array(x, dtype=complex)[indices]

    # Iterate over FFT stages
    for stage in range(stages):

        group_size = 2 ** (stage + 1)
        half_size = group_size // 2

        # Iterate over butterfly groups
        for group in range(0, N, group_size):

            # Iterate over butterflies within group
            for k in range(half_size):

                i = group + k
                j = i + half_size

                W = twiddles[stage][k]

                a = X[i]
                b = W * X[j]

                X[i] = a + b
                X[j] = a - b

    return X


# ============================================================
# FREQUENCY BAND PROCESSING
# ============================================================

def calculate_bands(X, bin_edges, method="max"):
    """Convert positive FFT bins into 8 frequency bands."""

    magnitude = np.abs(X[:len(X)//2 + 1])

    bands = np.zeros(8)

    for i in range(8):

        start = bin_edges[i]
        end = bin_edges[i + 1]

        values = magnitude[start:end]

        if method == "max":
            bands[i] = np.max(values)

        elif method == "rms":
            bands[i] = np.sqrt(np.mean(values**2))

        elif method == "energy":
            bands[i] = np.sqrt(np.sum(values**2))

        else:
            raise ValueError(f"Unknown method: {method}")

    return bands


def bands_to_matrix(bands):
    """
    Convert 8 normalized frequency bands (0–1)
    into an 8x8 LED matrix with brightness 0–255.
    """

    matrix = np.zeros((8, 8), dtype=np.uint8)

    for col, level in enumerate(bands):

        # Continuous height between 0 and 8
        height = np.clip(level * 8, 0, 8)

        for row in range(8):

            # Fraction of this LED that should be illuminated
            brightness = np.clip(height - row, 0, 1)

            matrix[row, col] = int(brightness * 255)

    return matrix

# ============================================================
# MAIN
# ============================================================

def main():

    # Precompute FFT parameters
    indices, twiddles = prepare_fft(N)

    # Convert frequency boundaries to FFT bin indices
    bin_edges = np.ceil(
        FREQ_EDGES * N / FS
    ).astype(int)

    # Include Nyquist bin in final band
    bin_edges[-1] = N // 2 + 1

    # Precompute Hann window
    window = np.hanning(N)

    # Previous band values for smoothing
    previous = np.zeros(8)

    # Initialize plot
    fig, ax = plt.subplots()

    matrix = np.zeros((8, 8))
    from matplotlib.colors import LinearSegmentedColormap

    # Black (off) → Yellow (full brightness)
    yellow_cmap = LinearSegmentedColormap.from_list(
        "yellow_led",
        ["#000000", "#FFFF00"]
    )

    img = ax.imshow(
        matrix,
        origin="lower",
        cmap=yellow_cmap,
        vmin=0,
        vmax=255,
        interpolation="nearest"
    )

    ax.set_xticks(range(8))
    ax.set_yticks(range(8))

    ax.set_xlabel("Frequency band")
    ax.set_ylabel("LED row")
    ax.set_title(f"1024-point FFT Spectrum Analyzer ({METHOD})")

    # Animation update function
    def update(frame):
        nonlocal previous

        audio, overflowed = stream.read(N)
        audio = audio[:, 0]

        # Remove DC offset
        audio = audio - np.mean(audio)

        # Apply Hann window
        audio_windowed = audio * window

        # Calculate FFT
        X = fft_iterative(
            audio_windowed,
            indices,
            twiddles
        )

        bands = calculate_bands(
        X,
        bin_edges,
        METHOD)

        # Normalize FFT amplitude
        bands /= np.sum(window) / 2

        BAND_GAIN = np.array([
            0.5,   # 0–125 Hz
            0.8,   # 125–250 Hz
            1.0,   # 250–500 Hz
            1.5,   # 500–1000 Hz
            2.0,   # 1000–2000 Hz
            2.5,   # 2000–4000 Hz
            3.0,   # 4000–8000 Hz
            4.0    # 8000–24000 Hz
            ])

        # Apply individual frequency-band gains
        bands *= BAND_GAIN

        # Convert to decibels
        bands_db = 20 * np.log10(
            np.maximum(bands, 1e-10)
        )
        # Find strongest band
        DB_MIN = -65
        DB_MAX = -15

        levels = np.clip(
    (bands_db - DB_MIN) / (DB_MAX - DB_MIN),
    0,
    1
)

        # Fast attack, slow decay
        attack = 0.90
        decay = 0.4

        alpha = np.where(
            levels > previous,
            attack,
            decay
        )

        levels = (
            alpha * levels
            + (1 - alpha) * previous
        )

        previous = levels.copy()

        # Convert to LED matrix
        matrix = bands_to_matrix(levels)

        img.set_data(matrix)

        return [img]

    # Start audio stream
    with sd.InputStream(
        samplerate=FS,
        channels=1,
        blocksize=N
    ) as stream:

        # Start animation
        ani = FuncAnimation(
            fig,
            update,
            interval=30,
            blit=True,
            cache_frame_data=False
        )

        plt.show()


if __name__ == "__main__":
    main()