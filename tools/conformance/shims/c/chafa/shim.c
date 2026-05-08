// Conformance shim for libchafa (C).
//
// chafa exposes a terminal-capability database via:
//   chafa_term_db_get_default()                -> ChafaTermDb (singleton)
//   chafa_term_db_detect(db, envp)             -> ChafaTermInfo for current terminal
//   chafa_term_info_have_seq(info, SEQ)        -> gboolean (lookup-only; doesn't probe)
//
// Detection mechanism: pure terminal-name/env-var database matching, no
// active probes. Capability set covered:
//   color_depth      : SET_COLOR_FG_DIRECT (truecolor) > _FG_256 > _FG_16 > none
//   hyperlinks       : BEGIN_HYPERLINK
//   graphics_sixel   : BEGIN_SIXELS
//   graphics_kitty   : BEGIN_KITTY_IMAGE_CHUNK
//   terminal_kind    : iterm2 inferred from BEGIN_ITERM2_IMAGE support
//
// All output is one schema-conforming JSON document at argv[1].

#include <chafa.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define SCHEMA_VERSION "0.1.0"
#define LIB_NAME "chafa"
#define LIB_VERSION "1.18.2"

/* JSON-escape a string into stdout. */
static void
json_str (FILE *f, const char *s)
{
    fputc ('"', f);
    if (!s)
    {
        fputs ("\"", f);
        return;
    }
    for (const char *p = s; *p; ++p)
    {
        unsigned char c = (unsigned char) *p;
        switch (c)
        {
            case '\\': fputs ("\\\\", f); break;
            case '"':  fputs ("\\\"", f); break;
            case '\n': fputs ("\\n", f); break;
            case '\r': fputs ("\\r", f); break;
            case '\t': fputs ("\\t", f); break;
            default:
                if (c < 0x20) fprintf (f, "\\u%04x", c);
                else fputc (c, f);
        }
    }
    fputc ('"', f);
}

static const char *
color_depth_for (ChafaTermInfo *info)
{
    if (chafa_term_info_have_seq (info, CHAFA_TERM_SEQ_SET_COLOR_FG_DIRECT))
        return "truecolor";
    if (chafa_term_info_have_seq (info, CHAFA_TERM_SEQ_SET_COLOR_FG_256))
        return "ansi256";
    if (chafa_term_info_have_seq (info, CHAFA_TERM_SEQ_SET_COLOR_FG_16))
        return "ansi16";
    return "none";
}

extern char **environ;

int
main (int argc, char **argv)
{
    const char *envelope_path = getenv ("CONFORMANCE_ENVELOPE");
    if (!envelope_path)
    {
        fprintf (stderr, "chafa-shim: $CONFORMANCE_ENVELOPE not set\n");
        return 2;
    }
    const char *output_path = argc > 1 ? argv[1] : "chafa.json";

    /* Slurp the envelope. */
    FILE *e = fopen (envelope_path, "rb");
    if (!e) { perror ("envelope"); return 2; }
    fseek (e, 0, SEEK_END);
    long elen = ftell (e);
    fseek (e, 0, SEEK_SET);
    char *envelope = malloc (elen + 1);
    if (!envelope) { fclose (e); return 1; }
    if (fread (envelope, 1, elen, e) != (size_t) elen) { fclose (e); free (envelope); return 1; }
    envelope[elen] = '\0';
    fclose (e);
    /* Strip trailing whitespace so the spliced JSON is clean. */
    while (elen > 0 && (envelope[elen - 1] == '\n' || envelope[elen - 1] == ' '
                        || envelope[elen - 1] == '\r' || envelope[elen - 1] == '\t'))
    {
        envelope[--elen] = '\0';
    }

    ChafaTermDb *db = chafa_term_db_get_default ();
    ChafaTermInfo *info = chafa_term_db_detect (db, environ);

    const char *color_value = color_depth_for (info);
    int has_hyperlink = chafa_term_info_have_seq (info, CHAFA_TERM_SEQ_BEGIN_HYPERLINK);
    int has_sixel     = chafa_term_info_have_seq (info, CHAFA_TERM_SEQ_BEGIN_SIXELS);
    int has_kitty     = chafa_term_info_have_seq (info, CHAFA_TERM_SEQ_BEGIN_KITTY_IMAGE_CHUNK);
    int has_iterm2    = chafa_term_info_have_seq (info, CHAFA_TERM_SEQ_BEGIN_ITERM2_IMAGE);

    FILE *out = fopen (output_path, "w");
    if (!out) { perror ("output"); free (envelope); return 1; }

    fputs ("{\n", out);
    fputs ("  \"schema_version\": ", out); json_str (out, SCHEMA_VERSION); fputs (",\n", out);
    fputs ("  \"run\": ", out); fputs (envelope, out); fputs (",\n", out);
    fputs ("  \"lib\": {\"name\": ", out); json_str (out, LIB_NAME);
    fputs (", \"version\": ", out); json_str (out, LIB_VERSION);
    fputs (", \"language\": \"c\", \"tier\": \"passive\"},\n", out);
    fputs ("  \"capabilities\": {\n", out);
    fputs ("    \"tty_stdin\":  {\"supported\": false},\n", out);
    fputs ("    \"tty_stdout\": {\"supported\": false},\n", out);
    fputs ("    \"tty_stderr\": {\"supported\": false},\n", out);
    fprintf (out, "    \"color_depth\": {\"supported\": true, \"value\": \"%s\", \"method\": \"chafa_term_info_have_seq cascade (FG_DIRECT > FG_256 > FG_16) on chafa_term_db_detect\", \"raw\": {\"have_FG_DIRECT\": %s, \"have_FG_256\": %s, \"have_FG_16\": %s}},\n",
             color_value,
             chafa_term_info_have_seq (info, CHAFA_TERM_SEQ_SET_COLOR_FG_DIRECT) ? "true" : "false",
             chafa_term_info_have_seq (info, CHAFA_TERM_SEQ_SET_COLOR_FG_256) ? "true" : "false",
             chafa_term_info_have_seq (info, CHAFA_TERM_SEQ_SET_COLOR_FG_16) ? "true" : "false");
    fputs ("    \"windows_console_color\": {\"supported\": false},\n", out);
    fputs ("    \"dimensions\": {\"supported\": false},\n", out);
    fputs ("    \"unicode\": {\"supported\": false},\n", out);
    if (has_iterm2)
    {
        fputs ("    \"terminal_kind\": {\"supported\": true, \"value\": \"iterm2\", \"method\": \"chafa BEGIN_ITERM2_IMAGE seq present\"},\n", out);
    }
    else
    {
        fputs ("    \"terminal_kind\": {\"supported\": false, \"raw\": \"chafa term-db: no BEGIN_ITERM2_IMAGE; lib does not classify other terminals\"},\n", out);
    }
    fputs ("    \"multiplexer\": {\"supported\": false},\n", out);
    fputs ("    \"theme\": {\"supported\": false},\n", out);
    fputs ("    \"background\": {\"supported\": false},\n", out);
    fprintf (out, "    \"hyperlinks\": {\"supported\": true, \"value\": \"%s\", \"method\": \"chafa BEGIN_HYPERLINK seq presence (term-db lookup)\"},\n",
             has_hyperlink ? "supported" : "unsupported");
    fputs ("    \"mouse\": {\"supported\": false},\n", out);
    fputs ("    \"keyboard\": {\"supported\": false},\n", out);
    fputs ("    \"clipboard_osc52\": {\"supported\": false},\n", out);
    fprintf (out, "    \"graphics_sixel\": {\"supported\": true, \"value\": %s, \"method\": \"chafa BEGIN_SIXELS seq presence (term-db lookup)\"},\n",
             has_sixel ? "true" : "false");
    fprintf (out, "    \"graphics_kitty\": {\"supported\": true, \"value\": %s, \"method\": \"chafa BEGIN_KITTY_IMAGE_CHUNK seq presence (term-db lookup)\"},\n",
             has_kitty ? "true" : "false");
    fputs ("    \"xtversion\": {\"supported\": false},\n", out);
    fputs ("    \"da1_attributes\": {\"supported\": false},\n", out);
    fputs ("    \"ci_detected\": {\"supported\": false}\n", out);
    fputs ("  }\n", out);
    fputs ("}\n", out);
    fclose (out);

    fprintf (stderr, "chafa-shim: wrote %s (color=%s sixel=%d kitty=%d iterm2=%d hyperlinks=%d)\n",
             output_path, color_value, has_sixel, has_kitty, has_iterm2, has_hyperlink);

    chafa_term_info_unref (info);
    free (envelope);
    return 0;
}
