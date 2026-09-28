/* Exercise a musl-linked indirect C call through the packaged libffi. */
#include <ffi.h>
#include <stdio.h>

static int add(int left, int right)
{
    return left + right;
}

int main(void)
{
    ffi_cif signature;
    ffi_type *parameters[2] = { &ffi_type_sint, &ffi_type_sint };
    int left = 19, right = 23, result = 0;
    void *arguments[2] = { &left, &right };

    if (ffi_prep_cif(&signature, FFI_DEFAULT_ABI, 2, &ffi_type_sint,
                     parameters) != FFI_OK) {
        fputs("libffi could not prepare a C call\n", stderr);
        return 1;
    }
    ffi_call(&signature, FFI_FN(add), &result, arguments);
    if (result != 42) {
        fputs("libffi returned the wrong result\n", stderr);
        return 1;
    }
    puts("LIBFFI_RUNTIME_READY");
    return 0;
}
