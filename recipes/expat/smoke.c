/* Exercise the staged Expat shared library through the NekoOS musl loader. */
#include <expat.h>
#include <stdio.h>
#include <string.h>

static int found_item;

static void XMLCALL on_start(void *user_data, const XML_Char *name,
                             const XML_Char **attributes)
{
    (void)user_data;
    if (strcmp(name, "item") == 0 && attributes[0] != NULL &&
        strcmp(attributes[0], "name") == 0 &&
        strcmp(attributes[1], "neko") == 0)
        ++found_item;
}

int main(void)
{
    static const char document[] = "<root><item name='neko'/></root>";
    XML_Parser parser = XML_ParserCreate(NULL);
    if (parser == NULL)
        return 1;
    XML_SetStartElementHandler(parser, on_start);
    int ok = XML_Parse(parser, document, (int)strlen(document), XML_TRUE);
    XML_ParserFree(parser);
    if (ok != XML_STATUS_OK || found_item != 1)
        return 1;
    puts("EXPAT_RUNTIME_READY");
    return 0;
}
