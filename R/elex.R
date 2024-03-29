library(xml2)
library(dplyr)

#' Recursive helper function to find time slots by following ANNOTATION_REF chains
#'
#' @param annotation_id The ID of the annotation for which to find time slots.
#' @param id_to_time_slot A named list mapping annotation IDs to their associated time slots.
#' @param id_to_annotation_ref A named list mapping annotation IDs to the IDs of the annotations they reference.
#' @return A vector containing two elements: `TIME_SLOT_REF1` and `TIME_SLOT_REF2`.
#' @examples
#' find_time_slots_recursively("ann0", id_to_time_slot, id_to_annotation_ref)
find_time_slots_recursively <- function(annotation_id, id_to_time_slot, id_to_annotation_ref) {
  if (annotation_id %in% names(id_to_time_slot)) {
    return(id_to_time_slot[[annotation_id]])
  } else if (annotation_id %in% names(id_to_annotation_ref)) {
    next_ref <- id_to_annotation_ref[[annotation_id]]
    return(find_time_slots_recursively(next_ref, id_to_time_slot, id_to_annotation_ref))
  } else {
    return(c(NA, NA))
  }
}



#' Calculate Duration Based on Time Slot References
#'
#' Calculates the absolute duration between two time slot references
#' by looking up their corresponding time values and subtracting them.
#' This ensures the duration is always positive, even if the time slots
#' are not in chronological order.
#'
#' @param time_slot_ref1 The reference ID for the first time slot.
#' @param time_slot_ref2 The reference ID for the second time slot.
#' @param time_slot_to_value A named vector mapping time slot IDs to their time values.
#' @return The absolute duration calculated as the difference between the time values of
#'         the second and first time slots. Returns NA if either time slot reference does not
#'         have an associated time value.
calculate_duration <- function(time_slot_ref1, time_slot_ref2, time_slot_to_value) {
  time_value1 <- as.numeric(time_slot_to_value[[time_slot_ref1]])
  time_value2 <- as.numeric(time_slot_to_value[[time_slot_ref2]])

  if (is.na(time_value1) || is.na(time_value2)) {
    return(NA)
  } else {
    # absolute value - sometimes the time_slots are not in the right order(?)
    return(abs(time_value2 - time_value1))
  }
}



#' Extract Annotations from an ELAN XML Document
#'
#' Parses an ELAN XML document to extract annotation details, organizing the information into a
#' structured tibble. Each row in the tibble represents an individual annotation. The function
#' handles both `ALIGNABLE_ANNOTATION` and `REF_ANNOTATION` types. It can optionally distribute
#' the duration of a parent annotation among its child annotations based on the `distribute_duration_among_children`
#' parameter.
#'
#' @param elan_xml An XML document object representing the ELAN file, loaded using `xml2::read_xml()`.
#' @param distribute_duration_among_children A logical parameter indicating whether to distribute
#'        the duration of parent annotations evenly among their child annotations. When `TRUE`,
#'        child annotations that reference the same parent will have their `DURATION` adjusted
#'        to reflect an equal share of the parent's total duration. Defaults to `FALSE`.
#' @return A tibble where each row represents an annotation and includes columns for linguistic
#'         references, annotation IDs, annotation values, time slots, and calculated durations.
#'         If `distribute_duration_among_children` is `TRUE`, durations for child annotations
#'         referencing the same parent are adjusted to distribute the parent's duration evenly
#'         among them.
extract_annotations <- function(elan_xml, distribute_duration_among_children = FALSE) {
  # Validate input
  if (!inherits(elan_xml, "xml_document")) {
    stop("Input must be an XML document object created by xml2::read_xml().")
  }

  # Extract and prepare mappings
  time_slots <- xml_find_all(elan_xml, "//TIME_SLOT")
  time_slot_to_value <- setNames(
    sapply(time_slots, xml_attr, "TIME_VALUE", USE.NAMES = FALSE),
    sapply(time_slots, xml_attr, "TIME_SLOT_ID", USE.NAMES = FALSE)
  )

  alignable_annotations <- xml_find_all(elan_xml, "//ALIGNABLE_ANNOTATION")

  id_to_time_slot <- setNames(
    lapply(alignable_annotations, function(node) c(xml_attr(node, "TIME_SLOT_REF1"), xml_attr(node, "TIME_SLOT_REF2"))),
    sapply(alignable_annotations, function(node) xml_attr(node, "ANNOTATION_ID"))
  )

  ref_annotations <- xml_find_all(elan_xml, "//REF_ANNOTATION")
  id_to_annotation_ref <- setNames(
    sapply(ref_annotations, function(node) xml_attr(node, "ANNOTATION_REF")),
    sapply(ref_annotations, function(node) xml_attr(node, "ANNOTATION_ID"))
  )

  annotations <- xml_find_all(elan_xml, "//TIER/*/*")

  data <- lapply(annotations, function(node) {
    tier_node <- xml_parent(xml_parent(node))
    annotation_id <- xml_attr(node, "ANNOTATION_ID")

    # using the helper function to find time slot references
    time_slots <- find_time_slots_recursively(annotation_id, id_to_time_slot, id_to_annotation_ref)
    time_slot_ref1 <- time_slots[1]
    time_slot_ref2 <- time_slots[2]

    # Looking up time values for the time slot references
    duration <- calculate_duration(time_slot_ref1, time_slot_ref2, time_slot_to_value)

    tibble(
      LANG_REF = xml_attr(tier_node, "DEFAULT_LOCALE"),
      LINGUISTIC_TYPE_REF = xml_attr(tier_node, "LINGUISTIC_TYPE_REF"),
      PARENT_REF = xml_attr(tier_node, "PARENT_REF"),
      TIER_ID = xml_attr(tier_node, "TIER_ID"),
      ANNOTATION_ID = annotation_id,
      ANNOTATION_REF = xml_attr(node, "ANNOTATION_REF"),
      PREVIOUS_ANNOTATION = xml_attr(node, "PREVIOUS_ANNOTATION"),
      TIME_SLOT_REF1 = time_slot_ref1,
      TIME_SLOT_REF2 = time_slot_ref2,
      ANNOTATION_VALUE = xml_text(xml_find_first(node, ".//ANNOTATION_VALUE")),
      anno_ref_numeric = ifelse(grepl("^ann\\d+$", annotation_id), as.numeric(gsub("ann", "", annotation_id, fixed = TRUE)), NA_real_),
      TIME_SLOT_REF1_TIME_VALUE = time_slot_to_value[[time_slot_ref1]],
      TIME_SLOT_REF2_TIME_VALUE = time_slot_to_value[[time_slot_ref2]],
      DURATION = duration)
  })

  # Preparing the data frame from the list of annotations
  annotations_df <- do.call(rbind, data) %>% as_tibble()

  # Conditionally distributing duration among child annotations if requested
  if (distribute_duration_among_children) {
    annotations_df <- annotations_df %>%
      group_by(ANNOTATION_REF, TIER_ID) %>%
      mutate(
        Child_Count = n(),
        DURATION = if_else(!is.na(ANNOTATION_REF) & Child_Count > 0, DURATION / Child_Count, DURATION)
      ) %>%
      ungroup() %>%
      select(-Child_Count)
  }

  return(annotations_df)
}
