% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/elex.R
\name{find_time_slots_recursively}
\alias{find_time_slots_recursively}
\title{Recursive helper function to find time slots by following ANNOTATION_REF chains}
\usage{
find_time_slots_recursively(
  annotation_id,
  id_to_time_slot,
  id_to_annotation_ref
)
}
\arguments{
\item{annotation_id}{The ID of the annotation for which to find time slots.}

\item{id_to_time_slot}{A named list mapping annotation IDs to their associated time slots.}

\item{id_to_annotation_ref}{A named list mapping annotation IDs to the IDs of the annotations they reference.}
}
\value{
A vector containing two elements: \code{TIME_SLOT_REF1} and \code{TIME_SLOT_REF2}.
}
\description{
Recursive helper function to find time slots by following ANNOTATION_REF chains
}
\examples{
find_time_slots_recursively("ann0", id_to_time_slot, id_to_annotation_ref)
}
