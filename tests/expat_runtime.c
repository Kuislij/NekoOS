/* Parse a small XML document with the packaged Expat library. */
#include <expat.h>
#include <stdio.h>
#include <string.h>

static void XMLCALL start_element(void *context, const XML_Char *name,
                                  const XML_Char **attributes)
{
    (void) attributes;
    if (strcmp(name, "neko") == 0)
        ++*(int *) context;
}

int main(void)
{
    static const char document[] = "<neko>ready</neko>";
    XML_Parser parser = XML_ParserCreate(NULL);
    if (parser == NULL)
        return 1;
    int elements = 0;
    XML_SetUserData(parser, &elements);
    XML_SetElementHandler(parser, start_element, NULL);
    enum XML_Status status = XML_Parse(parser, document,
                                       (int) (sizeof(document) - 1), XML_TRUE);
    XML_ParserFree(parser);
    if (status != XML_STATUS_OK || elements != 1) {
        fputs("Expat failed to parse the document\n", stderr);
        return 1;
    }
    puts("EXPAT_RUNTIME_READY");
    return 0;
}
