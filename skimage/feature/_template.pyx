"""template.py - Template matching
"""
import cython
cimport numpy as np
import numpy as np
from scipy.signal import fftconvolve
from skimage.transform import integral


cdef extern from "math.h":
    float sqrt(float x)
    float fabs(float x)


@cython.boundscheck(False)
cdef float sum_integral(np.ndarray[float, ndim=2,  mode="c"] sat,
        int r0, int c0, int r1, int c1):
    """
    Using a summed area table / integral image, calculate the sum
    over a given window.

    This function is the same as the `integrate` function in
    `skimage.transform.integrate`, but this Cython version significantly
    speeds up the code.

    Parameters
    ----------
    sat : ndarray of float
        Summed area table / integral image.
    r0, c0 : int
        Top-left corner of block to be summed.
    r1, c1 : int
        Bottom-right corner of block to be summed.

    Returns
    -------
    S : int
        Sum over the given window.
    """
    cdef float S = 0

    S += sat[r1, c1]

    if (r0 - 1 >= 0) and (c0 - 1 >= 0):
        S += sat[r0 - 1, c0 - 1]

    if (r0 - 1 >= 0):
        S -= sat[r0 - 1, c1]

    if (c0 - 1 >= 0):
        S -= sat[r1, c0 - 1]
    return S


@cython.boundscheck(False)
def match_template(np.ndarray[float, ndim=2, mode="c"] image,
                   np.ndarray[float, ndim=2, mode="c"] template,
                   str method):
    # convolve the image with template by frequency domain multiplication
    cdef np.ndarray[float, ndim=2] result
    # when `dtype=float` is used, ascontiguousarray returns ``double``.
    result = np.ascontiguousarray(fftconvolve(image, np.fliplr(template),
                                              mode="valid"), dtype=np.float32)

    # calculate squared integral images used for normalization
    cdef np.ndarray[float, ndim=2,  mode="c"] integral_sum
    cdef np.ndarray[float, ndim=2,  mode="c"] integral_sqr

    if method == 'norm-coeff':
        integral_sum = integral.integral_image(image)
    integral_sqr = integral.integral_image(image**2)

    # use inversed area for accuracy
    cdef float inv_area = 1.0 / (template.shape[0] * template.shape[1])
    cdef float template_norm
    cdef float template_mean = np.mean(template)

    if method == 'norm-corr':
        # calculate template norm according to the following:
        # variance = 1/K Sum[(x_k - mean) ** 2]
        #          = 1/K Sum[x_k ** 2] - mean ** 2
        #template_norm = sqrt((np.std(template) ** 2 +
                              #template_mean ** 2)) / sqrt(inv_area)
        # TODO: check equation for template_norm.
        # The above normalization factor is equivalent to the second-moment.
        template_norm = sqrt(np.sum(template**2))
    else:
        template_norm = sqrt((template_mean ** 2)) / sqrt(inv_area)

    # define window of template size in squared integral image
    cdef int i, j
    cdef float num, window_sum2, window_mean2, normed, t,
    # move window through convolution results, normalizing in the process
    for i in range(result.shape[0]):
        for j in range(result.shape[1]):
            num = result[i, j]
            i_end = i + template.shape[0]
            j_end = j + template.shape[1]

            window_mean2 = 0
            if method == 'norm-coeff':
                t = sum_integral(integral_sum, i, j, i_end, j_end)
                window_mean2 = t * t * inv_area
                num -= t*template_mean
            # calculate squared template window sum in the image
            window_sum2 = sum_integral(integral_sqr, i, j, i_end, j_end)

            normed = sqrt(window_sum2 - window_mean2) * template_norm
            # enforce some limits
            if fabs(num) < normed:
                num /= normed
            elif fabs(num) < normed*1.125:
                if num > 0:
                    num = 1
                else:
                    num = -1
            else:
                num = 0
            result[i, j] = num
    return result

