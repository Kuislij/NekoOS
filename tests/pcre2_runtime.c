/* Check that the packaged PCRE2 library matches UTF-8 text in the guest. */
#define PCRE2_CODE_UNIT_WIDTH 8
#include <pcre2.h>
#include <stdio.h>

int main(void)
{
    static const PCRE2_UCHAR pattern[] = "^neko[0-9]+$";
    static const PCRE2_UCHAR subject[] = "neko42";
    int error = 0;
    PCRE2_SIZE offset = 0;
    pcre2_code *code = pcre2_compile(pattern, PCRE2_ZERO_TERMINATED, 0,
                                     &error, &offset, NULL);
    if (code == NULL) {
        fprintf(stderr, "PCRE2 compile failed at %zu: %d\n", (size_t) offset, error);
        return 1;
    }
    pcre2_match_data *data = pcre2_match_data_create_from_pattern(code, NULL);
    if (data == NULL) {
        pcre2_code_free(code);
        return 1;
    }
    int result = pcre2_match(code, subject, PCRE2_ZERO_TERMINATED, 0, 0, data, NULL);
    pcre2_match_data_free(data);
    pcre2_code_free(code);
    if (result < 1) {
        fprintf(stderr, "PCRE2 did not match the expected text: %d\n", result);
        return 1;
    }
    puts("PCRE2_RUNTIME_READY");
    return 0;
}
