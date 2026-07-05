INTERFACE zif_mdmdoc_sap_reader
  PUBLIC.

  " Source adapter: decouples the comparator from where the SAP-side data (and
  " optionally the attached document) is read. Implementations: MDG change
  " request (ZCL_MDMDOC_MDG_READER), or manual/JSON (ZCL_MDMDOC_SAP_MANUAL).

  TYPES: BEGIN OF ty_attachment,
           name    TYPE string,
           ext     TYPE string,      " lowercase, no dot
           content TYPE xstring,
         END OF ty_attachment,
         tt_attachment TYPE STANDARD TABLE OF ty_attachment WITH EMPTY KEY.

  " SAP-side field values (SAP_KEYS) for the given change-request / master key.
  METHODS read_cr_fields
    IMPORTING iv_cr    TYPE string
    EXPORTING et_sap   TYPE zif_mdmdoc_types=>tt_sap_fields
              ev_found TYPE abap_bool
              ev_error TYPE string.

  " Attached documents of the change request (empty if unsupported / none).
  METHODS read_cr_attachments
    IMPORTING iv_cr    TYPE string
    EXPORTING et_docs  TYPE tt_attachment
              ev_error TYPE string.

ENDINTERFACE.
