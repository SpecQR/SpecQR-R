# Concrete supported AI metadata, matching the 50-AI SpecQR catalog.
.gs1_catalog <- local({
  add <- function(ai, label, n, variable, kind, check, role) {
    list(ai = ai, label = label, length = if (variable) list(type = "variable", min = 1L, max = n, is_variable = TRUE) else list(type = "fixed", exact = n, is_variable = FALSE),
         value_kind = kind, check_digit_rule = check, digital_link_role = role, separator = if (variable) "required-when-followed" else "none",
         digital_link_path_for_primary = if (role == "key-qualifier") "01" else NULL)
  }
  out <- list(
    add("00", "Serial shipping container code", 18L, FALSE, "numeric", "sscc", "primary-key"),
    add("01", "Global trade item number", 14L, FALSE, "numeric", "gtin", "primary-key"),
    add("02", "Contained trade item GTIN", 14L, FALSE, "numeric", "gtin", "data-attribute"),
    add("10", "Batch or lot number", 20L, TRUE, "text", "none", "key-qualifier"),
    add("11", "Production date", 6L, FALSE, "numeric", "none", "data-attribute"),
    add("12", "Due date", 6L, FALSE, "numeric", "none", "data-attribute"),
    add("13", "Packaging date", 6L, FALSE, "numeric", "none", "data-attribute"),
    add("15", "Best before date", 6L, FALSE, "numeric", "none", "data-attribute"),
    add("16", "Sell by date", 6L, FALSE, "numeric", "none", "data-attribute"),
    add("17", "Expiration date", 6L, FALSE, "numeric", "none", "data-attribute"),
    add("20", "Internal product variant", 2L, FALSE, "numeric", "none", "data-attribute"),
    add("21", "Serial number", 20L, TRUE, "text", "none", "key-qualifier"),
    add("22", "Consumer product variant", 20L, TRUE, "text", "none", "key-qualifier"),
    add("30", "Variable count", 8L, TRUE, "numeric", "none", "data-attribute"),
    add("37", "Count of contained trade items", 8L, TRUE, "numeric", "none", "data-attribute"),
    add("240", "Additional product identification", 30L, TRUE, "text", "none", "data-attribute"),
    add("241", "Customer part number", 30L, TRUE, "text", "none", "data-attribute"),
    add("400", "Customer purchase order number", 30L, TRUE, "text", "none", "data-attribute"),
    add("410", "Ship to global location number", 13L, FALSE, "numeric", "none", "data-attribute"),
    add("411", "Bill to global location number", 13L, FALSE, "numeric", "none", "data-attribute"),
    add("412", "Purchased from global location number", 13L, FALSE, "numeric", "none", "data-attribute"),
    add("413", "Ship for global location number", 13L, FALSE, "numeric", "none", "data-attribute"),
    add("414", "Identification of a physical location", 13L, FALSE, "numeric", "none", "primary-key"),
    add("415", "Global location number of the invoicing party", 13L, FALSE, "numeric", "none", "data-attribute"),
    add("420", "Ship to postal code", 20L, TRUE, "text", "none", "data-attribute"),
    add("422", "Country of origin", 3L, FALSE, "numeric", "none", "data-attribute"),
    add("424", "Country of processing", 3L, FALSE, "numeric", "none", "data-attribute"),
    add("425", "Country of disassembly", 3L, FALSE, "numeric", "none", "data-attribute"),
    add("426", "Country covering full process chain", 3L, FALSE, "numeric", "none", "data-attribute"),
    add("3100", "Net weight in kilograms", 6L, FALSE, "numeric", "none", "data-attribute"),
    add("3101", "Net weight in kilograms", 6L, FALSE, "numeric", "none", "data-attribute"),
    add("3102", "Net weight in kilograms", 6L, FALSE, "numeric", "none", "data-attribute"),
    add("3103", "Net weight in kilograms", 6L, FALSE, "numeric", "none", "data-attribute"),
    add("3104", "Net weight in kilograms", 6L, FALSE, "numeric", "none", "data-attribute"),
    add("3105", "Net weight in kilograms", 6L, FALSE, "numeric", "none", "data-attribute"),
    add("3200", "Net weight in pounds", 6L, FALSE, "numeric", "none", "data-attribute"),
    add("3201", "Net weight in pounds", 6L, FALSE, "numeric", "none", "data-attribute"),
    add("3202", "Net weight in pounds", 6L, FALSE, "numeric", "none", "data-attribute"),
    add("3203", "Net weight in pounds", 6L, FALSE, "numeric", "none", "data-attribute"),
    add("3204", "Net weight in pounds", 6L, FALSE, "numeric", "none", "data-attribute"),
    add("3205", "Net weight in pounds", 6L, FALSE, "numeric", "none", "data-attribute"),
    add("91", "Company internal information", 90L, TRUE, "text", "none", "data-attribute"),
    add("92", "Company internal information", 90L, TRUE, "text", "none", "data-attribute"),
    add("93", "Company internal information", 90L, TRUE, "text", "none", "data-attribute"),
    add("94", "Company internal information", 90L, TRUE, "text", "none", "data-attribute"),
    add("95", "Company internal information", 90L, TRUE, "text", "none", "data-attribute"),
    add("96", "Company internal information", 90L, TRUE, "text", "none", "data-attribute"),
    add("97", "Company internal information", 90L, TRUE, "text", "none", "data-attribute"),
    add("98", "Company internal information", 90L, TRUE, "text", "none", "data-attribute"),
    add("99", "Company internal information", 90L, TRUE, "text", "none", "data-attribute")
  )
  names(out) <- vapply(out, `[[`, "", "ai")
  out
})
get_supported_gs1_ais <- function() unname(.gs1_catalog)
get_gs1_ai_info <- function(ai) {
  if (!is.character(ai) || is.object(ai) || length(ai) != 1L || !is.null(dim(ai)) || is.na(ai)) return(NULL)
  .gs1_catalog[[ai]]
}
