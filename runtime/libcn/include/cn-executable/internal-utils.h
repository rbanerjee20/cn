#ifndef CN_UTILS
#define CN_UTILS

#ifdef __cplusplus
extern "C" {
#endif

enum cn_logging_level {
  CN_LOGGING_NONE = 0,
  CN_LOGGING_ERROR = 1,
  CN_LOGGING_INFO = 2
};


enum cn_logging_level get_cn_logging_level(void);

/** Sets the logging level, returning the previous one */
enum cn_logging_level set_cn_logging_level(enum cn_logging_level new_level);

enum cn_trace_granularity {
  CN_TRACE_NONE = 0,
  CN_TRACE_ENDS = 1,
  CN_TRACE_ALL = 2,
};

enum cn_trace_granularity get_cn_trace_granularity(void);

/** Sets the trace granularity, returning the previous one */
enum cn_trace_granularity set_cn_trace_granularity(
    enum cn_trace_granularity new_granularity);

void cn_print_nr_owned_predicates(void);

#ifdef __cplusplus
}
#endif

#endif 