import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../common/constant.dart';
import '../../../common/text_style.dart';
import '../../../controllers/invoices_controller.dart';
import '../../../controllers/terms_conditions_controller.dart';
import '../../../model/terms_conditions_model.dart';
import '../../utils/validators.dart';
import '../../../model/client_model.dart';
import '../../../model/invoice_model.dart';
import '../../../model/selling_service_model.dart';
import '../../../model/workspace_model.dart';
import '../../clients/manage_client_data/manage_client_data_screen.dart';
import '../../utils/custom_date_time_selector.dart';
import '../../widgets/add_payment_method_dialog.dart';
import '../../widgets/alert_dialog.dart';
import '../../widgets/billing_info_widget.dart';
import '../../widgets/container_shadow.dart';
import '../../widgets/custom_appbar.dart';
import '../../widgets/custom_bottom_sheet.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/custom_dialog.dart';
import '../../widgets/custom_icon_button.dart';
import '../../widgets/custom_popup_menu_item.dart';
import '../../widgets/custom_two_elements_wrap_widget.dart';
import '../../widgets/drop_down.dart';
import '../../widgets/edit_client_details_button.dart';
import '../../widgets/attachments_library_widget.dart';
import '../../widgets/loader.dart';
import '../../widgets/manage_selling_item_details_widget.dart';
import '../../widgets/pick_image_sheet.dart';
import '../../widgets/responsive_builder.dart';
import '../../widgets/selling_items_section_widget.dart';
import '../../widgets/snackbar.dart';
import '../../widgets/terms_conditions_picker_widget.dart';
import '../../widgets/text_field.dart';
import '../../widgets/totals_section_widget.dart';
import '../preview_invoice/preview_invoice_screen.dart';
import 'widgets/recurring_invoices_section_widget.dart';

class ManageInvoiceDetailsScreen extends StatefulWidget {
  final bool isEdit;
  final bool isEstimate;
  const ManageInvoiceDetailsScreen({
    super.key,
    this.isEdit = false,
    this.isEstimate = false,
  });

  @override
  State<ManageInvoiceDetailsScreen> createState() =>
      _ManageInvoiceDetailsScreenState();
}

class _ManageInvoiceDetailsScreenState
    extends State<ManageInvoiceDetailsScreen> {
  final InvoicesController invoicesController = Get.put(InvoicesController());
  final TermsConditionsController _termsConditionsController =
      Get.put(TermsConditionsController());
  final TextEditingController invoiceNameController = TextEditingController();
  final TextEditingController invoiceNotesController = TextEditingController();
  String currencySymbol = "\$";
  TextEditingController searchClientsTextController = TextEditingController();
  TextEditingController searchMethodsTextController = TextEditingController();

  DateFormat dateFormat = DateFormat("MM/dd/yyyy");

  bool isRecurrenceStarted = false, isEditEnabled = true;
  RxString recurrenceType = "".obs;
  RxString recurrenceStartDate = "".obs;
  RxString recurrenceEndDate = "".obs;

  RxBool showPaymentMethodWidget = false.obs;
  RxBool loading = false.obs;

  Rx<TermsConditionsModel> selectedTermsConditionsModel =
      TermsConditionsModel.empty().obs;

  setInvoiceDate(String date) {
    invoicesController.currentInvoiceModel.value.invoiceDate = date;
    // check if date is beyond invoiceDueDate, if yes then update invoiceDueDate to invoiceDate
    if (dateFormat.parse(date).isAfter(dateFormat
        .parse(invoicesController.currentInvoiceModel.value.invoiceDueDate))) {
      invoicesController.currentInvoiceModel.value.invoiceDueDate = date;
    }
    invoicesController.currentInvoiceModel.refresh();
  }

  setInvoiceDueDate(String date) {
    invoicesController.currentInvoiceModel.value.invoiceDueDate = date;
    invoicesController.currentInvoiceModel.refresh();
  }

  setInvoiceStatus(String status) {
    invoicesController.currentInvoiceModel.value.invoiceStatus = status;
    if (status == AppConstant.paid) {
      showPaymentMethodWidget.value = true;
    } else {
      showPaymentMethodWidget.value = false;
      invoicesController.currentInvoiceModel.value.paymentMethod = "";
    }
    invoicesController.currentInvoiceModel.refresh();
  }

  saveInvoice() async {
    var model = invoicesController.currentInvoiceModel.value;
    if (model.invoiceName.isEmpty) {
      ShowSnackBar.error("Please add invoice name");
      return;
    }
    if (!widget.isEdit) {
      if (invoicesController.currentClientModel.value.id.isEmpty) {
        ShowSnackBar.error("Please select a client");
        return;
      }
      if (model.servicesList.isEmpty) {
        ShowSnackBar.error("Please add atleast one item");
        return;
      }
    }
    if (model.invoiceStatus == AppConstant.paid &&
        model.paymentMethod.isEmpty) {
      ShowSnackBar.error("Please select a payment method");
      return;
    }
    bool isEstimateInvoice =
        invoicesController.currentInvoiceModel.value.estimateId.isNotEmpty;
    if (invoicesController.currentInvoiceModel.value.isRecurring) {
      String errorMessage = invoicesController.isValidRecurrenceData(
        isRecurrenceStarted: isRecurrenceStarted,
        recurrenceStartDate: recurrenceStartDate.value,
        recurrenceEndDate: recurrenceEndDate.value,
        recurrenceType: recurrenceType.value,
      );
      if (errorMessage.isNotEmpty) {
        ShowSnackBar.error(errorMessage);
        return;
      }
      Loader.showLoader();
      errorMessage = await invoicesController.isValidStripeData();
      Loader.hideLoader();
      if (errorMessage.isNotEmpty) {
        ShowSnackBar.error(errorMessage);
        return;
      }
    }

    Loader.showLoader();
    if (!widget.isEdit) {
      await invoicesController.createInvoiceDoc();
    }
    if (invoicesController.currentInvoiceModel.value.isRecurring) {
      await invoicesController.setInvoiceRecurrenceDataForSave(
        isRecurrenceStarted: isRecurrenceStarted,
        recurrenceType: recurrenceType.value,
        recurrenceStartDate: recurrenceStartDate.value,
        recurrenceEndDate: recurrenceEndDate.value,
      );
    } else {
      if (invoicesController
          .currentInvoiceModel.value.stripeScheduleSubscriptionId.isNotEmpty) {
        await invoicesController.checkForCancelingRecurringInvoice(
            isEditEnabled: isEditEnabled);
      }
    }
    await invoicesController.saveInvoiceData(
      isEdit: widget.isEdit,
      isEstimateInvoice: isEstimateInvoice,
    );
    Loader.hideLoader();
  }

  bool checkShowCancelRecurringOption() {
    var invoice = invoicesController.currentInvoiceModel.value;
    debugPrint("####${invoice.recurringInvoiceStartDateTimestamp}");
    if (widget.isEdit &&
        invoice.isRecurring &&
        invoice.recurrenceMainReferenceInvoiceDocId.isEmpty &&
        invoice.stripeScheduleSubscriptionId.isNotEmpty) {
      return true;
    }
    return false;
  }

  @override
  void initState() {
    debugPrint("initState");
    currencySymbol = invoicesController
        .workspaceDetailsController.workspaceModel.value.currencyModel.symbol;
    invoiceNameController.clear();
    invoiceNotesController.clear();
    if (!widget.isEdit && !widget.isEstimate) {
      invoicesController.setCreateInvoiceDefaultData();
    } else {
      invoiceNameController.text =
          invoicesController.currentInvoiceModel.value.invoiceName;
      invoiceNotesController.text =
          invoicesController.currentInvoiceModel.value.notes;
    }
    if (widget.isEdit) {
      if (invoicesController.currentInvoiceModel.value
          .stripeSubscriptionIntervalName.isNotEmpty) {
        recurrenceType.value = invoicesController
            .formatIntervalNameToRecurrenceTypeValue(invoicesController
                .currentInvoiceModel.value.stripeSubscriptionIntervalName);
        if (recurrenceType.value == RecurrenceType.every_week.value &&
            invoicesController.currentInvoiceModel.value
                    .stripeSubscriptionIntervalCount ==
                2) {
          recurrenceType.value = RecurrenceType.every_2_weeks.value;
        }
      }
      if (invoicesController
              .currentInvoiceModel.value.recurringInvoiceStartDateTimestamp >
          0) {
        recurrenceStartDate.value = DateFormat("MM/dd/yyyy").format(
            DateTime.fromMillisecondsSinceEpoch(invoicesController
                    .currentInvoiceModel
                    .value
                    .recurringInvoiceStartDateTimestamp *
                1000));
        int nowTimestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        if (nowTimestamp >
            invoicesController
                .currentInvoiceModel.value.recurringInvoiceStartDateTimestamp) {
          isRecurrenceStarted = true;
        }
      }
      if (invoicesController
              .currentInvoiceModel.value.recurringInvoiceEndDateTimestamp >
          0) {
        recurrenceEndDate.value = DateFormat("MM/dd/yyyy").format(
            DateTime.fromMillisecondsSinceEpoch(invoicesController
                    .currentInvoiceModel
                    .value
                    .recurringInvoiceEndDateTimestamp *
                1000));
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!invoicesController.isDataAvailable.value) {
        invoicesController.isLoading.value = true;
        await invoicesController.getAllServices();
        invoicesController.isDataAvailable.value = true;
        invoicesController.isLoading.value = false;
      }
      if (!_termsConditionsController.dataAvailable.value) {
        loading.value = true;
        await _termsConditionsController.getTermsConditionsList();
        loading.value = false;
      }
      if (!widget.isEdit) {
        int index = _termsConditionsController.termsConditionsList
            .indexWhere((element) => element.isDefaultInvoice == true);
        if (index != -1) {
          var termsConditions =
              _termsConditionsController.termsConditionsList[index];
          invoicesController.currentInvoiceModel.value.termsConditionsId =
              termsConditions.id;
          selectedTermsConditionsModel.value =
              TermsConditionsModel.fromMap(termsConditions.toMap());
        }
      } else {
        int index = _termsConditionsController.termsConditionsList.indexWhere(
            (element) =>
                element.id ==
                invoicesController.currentInvoiceModel.value.termsConditionsId);
        if (index == -1) {
          invoicesController.currentInvoiceModel.value.termsConditionsId = "";
        } else {
          selectedTermsConditionsModel.value = TermsConditionsModel.fromMap(
              _termsConditionsController.termsConditionsList[index].toMap());
        }
      }
    });
    super.initState();
  }

  @override
  void dispose() {
    invoicesController.clearData();
    super.dispose();
  }

  Widget _buildActionsButton() {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 10),
      child: PopupMenuButton(
        position: PopupMenuPosition.under,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        itemBuilder: (context) {
          return [
            CustomPopupMenuItem(
              onTap: () {
                Future.delayed(
                  Duration.zero,
                  () {
                    Get.to(
                      () => PreviewInvoiceScreen(
                        termsConditionsModel:
                            selectedTermsConditionsModel.value,
                      ),
                      transition: Transition.noTransition,
                    );
                  },
                );
              },
              value: "preview",
              child: const Row(
                children: [
                  Icon(Icons.preview_rounded),
                  SizedBox(width: 10),
                  Text("Preview"),
                ],
              ),
            ),
            ..._buildSaveOptionsList()
          ];
        },
        child: IgnorePointer(
          child: CustomButton(
            width: 100,
            text: "Actions",
            function: () async {},
          ),
        ),
      ),
    );
  }

  bool showRecurringInvoicesSection(InvoiceModel invoiceModel) {
    return invoiceModel.isRecurring &&
        invoiceModel.recurrenceMainReferenceInvoiceDocId.isEmpty &&
        widget.isEdit;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      appBar: customAppBar(
        title: !widget.isEdit ? "New Invoice" : "Edit Invoice",
        context: context,
        isBack: true,
        showWebNavBar: false,
        action: _buildActionsButton(),
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1000),
          margin: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [containerShadow(context)],
          ),
          child: Obx(() {
            InvoiceModel invoiceModel =
                invoicesController.currentInvoiceModel.value;
            return invoicesController.isLoading.value == true || loading.value
                ? const LoadingWidget()
                : GestureDetector(
                    onTap: () {
                      FocusScope.of(context).requestFocus(FocusNode());
                    },
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(15),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ResponsiveBuilder.isMobile(context)
                              ? _buildMobileInvNameAndActions()
                              : _buildLargeScreensInvNameAndActions(),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .primaryColor
                                  .withOpacity(0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  "Invoice Details",
                                  style: TextStyles.titleMedium,
                                ),
                                Text(
                                  "Invoice # ${invoiceModel.invoiceNumber}",
                                  style: TextStyles.labelLarge,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          ResponsiveBuilder.isMobile(context)
                              ? _buildMobileBillingInfo()
                              : _buildDesktopBillingInfo(),
                          const SizedBox(height: 20),
                          _buildInvoiceDatesWidget(invoiceModel: invoiceModel),
                          const SizedBox(height: 20),
                          _buildInvoiceStatusWidget(invoiceModel: invoiceModel),
                          const SizedBox(height: 20),
                          if (showPaymentMethodWidget.value)
                            _buildChooseMethodWidget(),
                          if (showPaymentMethodWidget.value)
                            const SizedBox(height: 20),
                          if (invoiceModel
                              .recurrenceMainReferenceInvoiceDocId.isEmpty)
                            _buildInvoiceRecurrenceDataWidget(
                                invoiceModel: invoiceModel),
                          if (invoiceModel
                              .recurrenceMainReferenceInvoiceDocId.isEmpty)
                            const SizedBox(height: 20),
                          SellingItemsSectionWidget(
                            currentServicesList: invoiceModel.servicesList,
                            allServicesList:
                                invoicesController.allInvoiceServicesList,
                            onDeleteItem: (index) => invoicesController
                                .deleteItemFromInvoice(index: index),
                            onUpdateItem: ({
                              isEdit = true,
                              itemDescription = "",
                              itemName = "",
                              unitPrice = 0,
                              units = 0,
                              index = 0,
                            }) {
                              invoicesController.updateInvoiceItems(
                                itemName: itemName,
                                itemDescription: itemDescription,
                                units: units,
                                unitPrice: unitPrice,
                                isEdit: isEdit,
                                itemIndex: index,
                              );
                            },
                            currencySymbol: currencySymbol,
                          ),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerRight,
                            child: CustomIconButton(
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (context) {
                                    return CustomDialog(
                                      child: ManageSellingItemDetailsWidget(
                                        serviceIndex: -1,
                                        isEdit: false,
                                        serviceModel:
                                            SellingServiceModel.empty(),
                                        allServicesList: invoicesController
                                            .allInvoiceServicesList,
                                        updateItemCallback: ({
                                          isEdit = false,
                                          itemDescription = "",
                                          itemName = "",
                                          unitPrice = 0,
                                          units = 0,
                                          index = 0,
                                        }) =>
                                            invoicesController
                                                .updateInvoiceItems(
                                          isEdit: false,
                                          itemDescription: itemDescription,
                                          itemName: itemName,
                                          unitPrice: unitPrice,
                                          units: units,
                                          itemIndex: -1,
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                              icon:
                                  const Icon(Icons.add_circle_outline_outlined),
                              label: "Add New Item",
                            ),
                          ),
                          const SizedBox(height: 20),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TotalsSectionWidget(
                              subTotalValue: invoiceModel.subTotal,
                              discountValue:
                                  invoiceModel.discountPercentageEnabled
                                      ? invoiceModel.discountPercentage
                                      : invoiceModel.discountAmount,
                              taxValue: invoiceModel.taxPercentage,
                              totalValue: invoiceModel.total,
                              depositValue:
                                  invoiceModel.depositPercentageEnabled
                                      ? invoiceModel.depositPercentage
                                      : invoiceModel.depositAmount,
                              amountValue: (invoiceModel.total -
                                      invoiceModel.depositAmount)
                                  .toPrecision(2),
                              discountPercentageEnabled:
                                  invoiceModel.discountPercentageEnabled,
                              depositPercentageEnabled:
                                  invoiceModel.depositPercentageEnabled,
                              onDiscountValueChanged: (value) {
                                if (invoiceModel.discountPercentageEnabled) {
                                  invoiceModel.discountPercentage = value;
                                } else {
                                  invoiceModel.discountAmount = value;
                                }
                                invoicesController.updateInvoiceTotals();
                              },
                              onTaxValueChanged: (value) {
                                invoiceModel.taxPercentage = value;
                                invoicesController.updateInvoiceTotals();
                              },
                              onDepositValueChanged: (value) {
                                if (invoiceModel.depositPercentageEnabled) {
                                  invoiceModel.depositPercentage = value;
                                } else {
                                  invoiceModel.depositAmount = value;
                                }
                                invoicesController.updateInvoiceTotals();
                              },
                              onDiscountPercentageEnabledChanged: (value) {
                                invoicesController
                                    .updateDiscountPercentageEnabled(value);
                              },
                              onDepositPercentageEnabledChanged: (value) {
                                invoicesController
                                    .updateDepositPercentageEnabled(value);
                              },
                              currencySymbol: currencySymbol,
                              isDepositPaid: invoiceModel.isDepositPaid,
                            ),
                          ),
                          if (showRecurringInvoicesSection(invoiceModel))
                            const SizedBox(height: 20),
                          if (showRecurringInvoicesSection(invoiceModel))
                            RecurringInvoicesSectionWidget(
                              mainInvoice: invoiceModel,
                            ),
                          const SizedBox(height: 20),
                          _buildNotesSectionWidget(),
                          const SizedBox(height: 20),
                          if (selectedTermsConditionsModel.value.id.isNotEmpty)
                            Row(
                              children: [
                                Text(
                                  "Selected Terms & Conditions:",
                                  style: TextStyles.titleSmall,
                                ),
                                const SizedBox(width: 10),
                                Flexible(
                                  child: Text(
                                    selectedTermsConditionsModel.value.title,
                                    style: TextStyles.bodyMedium,
                                  ),
                                )
                              ],
                            ),
                          if (selectedTermsConditionsModel.value.id.isNotEmpty)
                            const SizedBox(height: 20),
                          CustomButton(
                            text: "Terms & Conditions",
                            function: () async {
                              customBottomSheet(
                                fullScreen: false,
                                context: context,
                                builder: (context) {
                                  return TermsConditionsPickerWidget(
                                    currentTermsConditions:
                                        invoiceModel.termsConditionsId,
                                    onSelected: (value) {
                                      invoiceModel.termsConditionsId = value;
                                      int index = _termsConditionsController
                                          .termsConditionsList
                                          .indexWhere(
                                              (element) => element.id == value);
                                      if (index != -1) {
                                        selectedTermsConditionsModel.value =
                                            TermsConditionsModel.fromMap(
                                                _termsConditionsController
                                                    .termsConditionsList[index]
                                                    .toMap());
                                        invoicesController.currentInvoiceModel
                                            .refresh();
                                      }
                                    },
                                    termsConditionsList:
                                        _termsConditionsController
                                            .termsConditionsList,
                                  );
                                },
                              );
                            },
                          ),
                          const SizedBox(height: 20),
                          GestureDetector(
                            onTap: () {
                              showModalBottomSheet(
                                  isScrollControlled: true,
                                  shape: const RoundedRectangleBorder(
                                    borderRadius: BorderRadius.only(
                                      topLeft: Radius.circular(25),
                                      topRight: Radius.circular(25),
                                    ),
                                  ),
                                  constraints: BoxConstraints(
                                    maxWidth:
                                        ResponsiveBuilder.isMobile(context)
                                            ? Get.width
                                            : 1000,
                                  ),
                                  backgroundColor: Colors.transparent,
                                  context: context,
                                  builder: (BuildContext context) {
                                    return PickImageSheet(
                                      onCamera: () {
                                        invoicesController.getInvoiceAttachment(
                                            imageSource: ImageSource.camera);
                                      },
                                      onGallery: () {
                                        invoicesController.getInvoiceAttachment(
                                            imageSource: ImageSource.gallery);
                                      },
                                      onFile: () {
                                        invoicesController.getInvoiceAttachment(
                                          imageSource: ImageSource.gallery,
                                          file: true,
                                        );
                                      },
                                    );
                                  });
                            },
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              width: double.infinity,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: Theme.of(context).primaryColor,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: [containerShadow(context)],
                              ),
                              child: Text(
                                "Invoice Attachments",
                                style: TextStyles.titleSmall.copyWith(
                                  color:
                                      Theme.of(context).colorScheme.onPrimary,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          if (invoicesController
                              .currentInvoiceModel.value.attachments.isNotEmpty)
                            AttachmentsLibraryWidget(
                              attachmentsList: (invoicesController
                                      .currentInvoiceModel.value.attachments)
                                  .obs,
                              onRemove:
                                  invoicesController.deleteInvoiceAttachment,
                            ),
                        ],
                      ),
                    ),
                  );
          }),
        ),
      ),
    );
  }

  List<PopupMenuEntry> _buildSaveOptionsList() {
    return [
      CustomPopupMenuItem(
        value: "Save & Exit",
        onTap: () async {
          Future.delayed(
            Duration.zero,
            () async {
              await saveInvoice();
              if (!Get.isSnackbarOpen) {
                Get.back();
              }
            },
          );
        },
        child: const Row(
          children: [
            Icon(Icons.exit_to_app_rounded),
            SizedBox(width: 10),
            Text("Save & Exit"),
          ],
        ),
      ),
      CustomPopupMenuItem(
        value: 'link',
        onTap: () {
          Future.delayed(
            Duration.zero,
            () async {
              await saveInvoice();
              if (!Get.isSnackbarOpen) {
                var model = invoicesController.currentInvoiceModel.value;
                Clipboard.setData(
                  ClipboardData(
                    text:
                        "${AppConstant.invoicesPublicLinkPrefix}${model.workspaceId}-${model.id}",
                  ),
                );
                Get.back();
                ShowSnackBar.success("Link copied to clipboard");
              }
            },
          );
        },
        child: Row(
          children: [
            Icon(
              Icons.link,
              color: Theme.of(context).iconTheme.color,
            ),
            const SizedBox(width: 10),
            const Text(
              'Save & Copy Link',
            ),
          ],
        ),
      ),
      /* PopupMenuItem(
        value: "Save & Send",
        onTap: () async {
          Future.delayed(
            Duration.zero,
            () async {
              await saveInvoice();
              if (!Get.isSnackbarOpen) {
                EmailTemplateController emailTemplateController =
                    Get.put(EmailTemplateController());
                Loader.showLoader();
                await emailTemplateController.getInvoiceEmailTemplate();
                Loader.hideLoader();
                var invModel = invoicesController.currentInvoiceModel.value;
                var clientModel = invoicesController.currentClientModel.value;
                String invoiceTotal =
                    "$currencySymbol${(!invModel.isDepositPaid) ? invModel.total : (invModel.total - invModel.depositAmount).toStringAsFixed(2)}";
                String invoiceTemplateBody = emailTemplateController
                    .invoiceEmailBodyController.value.text;
                String invoiceTemplateSubject = emailTemplateController
                    .invoiceEmailSubjectController.value.text;
                String workspaceImageUrl = invoicesController
                    .workspaceDetailsController
                    .workspaceModel
                    .value
                    .info
                    .imageUrl;
                Get.to(
                  () => SendEmailScreen(
                    clientEmail: invModel.clientEmail,
                    clientFirstName: clientModel.firstName,
                    clientLastName: clientModel.lastName,
                    clientFullName: invModel.clientFullName,
                    clientPhone: invModel.clientPhone.internationalNumber,
                    clientAddress: invModel.clientAddress,
                    emailSubject: invoiceTemplateSubject,
                    emailBodyTemplate: invoiceTemplateBody,
                    workspaceName: invModel.workspaceName,
                    workspaceAddress: invModel.workspaceAddress,
                    workspacePhone: invModel.workspacePhone.internationalNumber,
                    workspaceImageUrl: workspaceImageUrl,
                    actionButtonLink:
                        AppConstant.invoicesPublicLinkPrefix + invModel.id,
                    header: "Invoice",
                    total: invoiceTotal,
                    serviceNamesList: invModel.servicesList
                        .map((e) => e.serviceName)
                        .toList(),
                  ),
                );
              }
            },
          );
        },
        child: const Row(
          children: [
            Icon(Icons.send_rounded),
            SizedBox(width: 10),
            Text("Save & Send"),
          ],
        ),
      ), */
      /* PopupMenuItem(
        child: Row(
          children: [
            Icon(Icons.download_rounded),
            SizedBox(width: 10),
            Text("Save & Download"),
          ],
        ),
        value: "Save & Download",
        onTap: () async {
          Future.delayed(
            Duration.zero,
            () async {
              await saveInvoice();
              var invModel = invoicesController.currentInvoiceModel.value;
              DateTime dateTime = DateTime.now();
              String fileName =
                  "${invModel.clientFullName}'s Invoice${dateTime.toString().replaceAll("-", "_").replaceFirst(".", " ").replaceAll(":", " ")}.pdf";
              var pdfBytes = Uint8List(0); //await invoiceGeneratePdf();
              if (!kIsWeb) {
                PdfApi.saveDocument(
                  name: fileName,
                  pdfFileBytes: pdfBytes,
                );
              } else {
                await FileSaver.instance.saveFile(
                  name: fileName,
                  ext: "pdf",
                  bytes: pdfBytes,
                );
              }
              Get.back();
              ShowSnackBar.success("Invoice Pdf Downloaded Successfully");
            },
          );
        },
      ), */
    ];
  }

  Widget _buildSaveButton({required double width}) {
    return PopupMenuButton(
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      itemBuilder: (context) {
        return _buildSaveOptionsList();
      },
      child: IgnorePointer(
        child: CustomButton(
          width: width,
          text: "Save",
          function: () async {},
        ),
      ),
    );
  }

  Widget _buildMobileInvNameAndActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Invoice Name",
          style: TextStyles.titleMedium,
        ),
        const SizedBox(height: 10),
        CustomTextField(
          hintText: "Invoice Name",
          controller: invoiceNameController,
          onChange: (text) {
            invoicesController.currentInvoiceModel.value.invoiceName = text;
          },
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildLargeScreensInvNameAndActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Invoice Name",
          style: TextStyles.titleMedium,
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: CustomTextField(
                height: 45,
                hintText: "Invoice Name",
                controller: invoiceNameController,
                onChange: (text) {
                  invoicesController.currentInvoiceModel.value.invoiceName =
                      text;
                },
              ),
            ),
            const SizedBox(width: 10),
            CustomButton(
              width: 200,
              color: Theme.of(context).scaffoldBackgroundColor,
              fontColor: Theme.of(context).colorScheme.onSurface,
              text: "Preview",
              function: () async {
                Get.to(
                  () => PreviewInvoiceScreen(
                    termsConditionsModel: selectedTermsConditionsModel.value,
                  ),
                  transition: Transition.noTransition,
                );
              },
            ),
            const SizedBox(width: 10),
            _buildSaveButton(width: 200),
            const SizedBox(height: 20),
          ],
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildWorkspaceBillingInfoWidget({
    required WorkspaceModel workspaceModel,
  }) {
    return BillingInfoWidget(
      name: workspaceModel.info.name,
      email: workspaceModel.info.email,
      address: workspaceModel.locationData.address.formattedAddress,
      phone: workspaceModel.phoneModel.internationalNumber,
      isWorkspace: true,
    );
  }

  bool checkShowMoreClientDetails({required ClientModel clientModel}) {
    if (clientModel.phoneNumbers.length > 1 ||
        clientModel.addresses.length > 1 ||
        clientModel.emails.length > 1) {
      return true;
    }
    return false;
  }

  Widget _buildClientBillingInfoWidget({
    required ClientModel clientModel,
    required InvoiceModel invoiceModel,
  }) {
    bool isDesktop = ResponsiveBuilder.isDesktop(context);
    return Column(
      crossAxisAlignment:
          !isDesktop ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      children: [
        BillingInfoWidget(
          name: invoiceModel.clientFullName,
          address: invoiceModel.clientAddress,
          email: invoiceModel.clientEmail,
          phone: invoiceModel.clientPhone.internationalNumber,
          isWorkspace: false,
        ),
        if (checkShowMoreClientDetails(clientModel: clientModel))
          Padding(
            padding: const EdgeInsetsDirectional.only(bottom: 0),
            child: EditClientDetailsButton(
              emails: clientModel.id.isNotEmpty
                  ? clientModel.emails.map((e) => e.email).toList()
                  : [invoiceModel.clientEmail],
              addresses: clientModel.id.isNotEmpty
                  ? clientModel.addresses
                      .map((e) => e.formattedAddress)
                      .toList()
                  : [invoiceModel.clientAddress],
              phones: clientModel.id.isNotEmpty
                  ? clientModel.phoneNumbers
                      .map((e) => e.internationalNumber)
                      .toList()
                  : [invoiceModel.clientPhone.internationalNumber],
              primaryAddressIndex: clientModel.id.isNotEmpty
                  ? clientModel.addresses
                      .indexWhere((element) => element.isPrimary)
                  : 0,
              primaryEmailIndex: clientModel.id.isNotEmpty
                  ? clientModel.emails
                      .indexWhere((element) => element.isPrimary)
                  : 0,
              primaryPhoneIndex: clientModel.id.isNotEmpty
                  ? clientModel.phoneNumbers
                      .indexWhere((element) => element.isPrimary)
                  : 0,
              onSelectAddress: (address) =>
                  invoicesController.setClientAddress(address),
              onSelectEmail: (email) =>
                  invoicesController.setClientEmail(email),
              onSelectPhone: (phone) =>
                  invoicesController.setClientPhone(phone),
              selectedAddress: invoiceModel.clientAddress,
              selectedEmail: invoiceModel.clientEmail,
              selectedPhone: invoiceModel.clientPhone.internationalNumber,
            ),
          ),
      ],
    );
  }

  Widget _buildChooseClientDropDown({required String selectedClientName}) {
    return CustomDropdownButton(
      searchable: true,
      textEditingController: searchClientsTextController,
      buttonWidth: 300,
      dropdownWidth: 300,
      hint: "Choose Client",
      dropdownItems: invoicesController.clientsController.clientsData
          .map((client) => client.fullName)
          .toList(),
      items: [
        DropdownMenuItem<String>(
          alignment: Alignment.topCenter,
          value: "Add customer",
          child: Container(
            // width: 550,
            padding: EdgeInsets.zero,
            alignment: Alignment.center,
            child: FilledButton.icon(
              onPressed: () {
                Get.to(
                  () => const ManageClientDataScreen(
                    isEdit: false,
                    isInvoice: true,
                  ),
                  routeName: AppConstant.addClientScreen,
                );
              },
              icon: const Icon(Icons.add_circle_outline_outlined),
              label: const Text("Create New Client"),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          onTap: () {
            // Add your functionality here for "Add customer"
          },
        ),
        ...invoicesController.clientsController.clientsData
            .map<DropdownMenuItem<String>>(
          (client) {
            return DropdownMenuItem<String>(
                value: client.fullName,
                child: Text(client.fullName, style: TextStyles.bodyMedium));
          },
        ),
      ],
      value: selectedClientName.isEmpty ? null : selectedClientName,
      onChanged: (value) {
        invoicesController.setClientData(value!);
      },
    );
  }

  Widget _buildMobileBillingInfo() {
    return Obx(() {
      var workspaceModel =
          invoicesController.workspaceDetailsController.workspaceModel.value;
      var clientModel = invoicesController.currentClientModel.value;
      var invoiceModel = invoicesController.currentInvoiceModel.value;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildWorkspaceBillingInfoWidget(workspaceModel: workspaceModel),
          Divider(
            color: Theme.of(context).dividerColor,
            thickness: 1,
            height: 1,
          ),
          if (!widget.isEdit)
            Column(
              children: [
                const SizedBox(height: 10),
                _buildChooseClientDropDown(
                    selectedClientName: invoiceModel.clientFullName),
              ],
            ),
          const SizedBox(height: 10),
          if (invoiceModel.clientId.isNotEmpty)
            _buildClientBillingInfoWidget(
              clientModel: clientModel,
              invoiceModel: invoiceModel,
            ),
          if (!widget.isEdit)
            Column(
              children: [
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: CustomIconButton(
                    onPressed: () {
                      Get.to(
                        () => const ManageClientDataScreen(
                          isEdit: false,
                          isInvoice: true,
                        ),
                        routeName: AppConstant.addClientScreen,
                      );
                    },
                    icon: const Icon(Icons.add_circle_outline_outlined),
                    label: "Create New Client",
                  ),
                ),
              ],
            ),
        ],
      );
    });
  }

  Widget _buildDesktopBillingInfo() {
    return Obx(() {
      var workspaceModel =
          invoicesController.workspaceDetailsController.workspaceModel.value;
      var clientModel = invoicesController.currentClientModel.value;
      var invoiceModel = invoicesController.currentInvoiceModel.value;
      return Column(
        children: [
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _buildWorkspaceBillingInfoWidget(
                      workspaceModel: workspaceModel),
                ),
                VerticalDivider(
                  color: Theme.of(context).dividerColor,
                  thickness: 1,
                  width: 1,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      if (!widget.isEdit)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            _buildChooseClientDropDown(
                                selectedClientName:
                                    invoiceModel.clientFullName),
                            const SizedBox(height: 10),
                          ],
                        ),
                      if (invoiceModel.clientId.isNotEmpty)
                        _buildClientBillingInfoWidget(
                          clientModel: clientModel,
                          invoiceModel: invoiceModel,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (!widget.isEdit)
            Column(
              children: [
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerRight,
                  child: CustomIconButton(
                    onPressed: () {
                      Get.to(
                        () => const ManageClientDataScreen(
                          isEdit: false,
                          isInvoice: true,
                        ),
                        routeName: AppConstant.addClientScreen,
                      );
                    },
                    icon: const Icon(Icons.add_circle_outline_outlined),
                    label: "Create New Client",
                  ),
                ),
              ],
            ),
        ],
      );
    });
  }

  Widget _buildInvoiceDatesWidget({required InvoiceModel invoiceModel}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                "Invoice Date",
                style: TextStyles.titleSmall,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                "Payment Due",
                style: TextStyles.titleSmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () async {
                  String date = await CustomDateTimeSelector.selectDate(
                    context: context,
                    initialDate: dateFormat.parse(invoiceModel.invoiceDate),
                  );
                  setInvoiceDate(date);
                },
                child: Container(
                  height: 45,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.tertiaryContainer,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          invoiceModel.invoiceDate,
                          style: TextStyles.titleMedium.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Icon(
                          Icons.calendar_month_outlined,
                          color: Theme.of(context).colorScheme.primary,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: InkWell(
                onTap: () async {
                  String date = await CustomDateTimeSelector.selectDate(
                    context: context,
                    initialDate: dateFormat.parse(invoiceModel.invoiceDueDate),
                    passFirstDate: dateFormat.parse(invoiceModel.invoiceDate),
                  );
                  setInvoiceDueDate(date);
                },
                child: Container(
                  height: 45,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.tertiaryContainer,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          invoiceModel.invoiceDueDate,
                          style: TextStyles.titleMedium.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Icon(
                          Icons.calendar_month_outlined,
                          color: Theme.of(context).colorScheme.primary,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInvoiceStatusWidget({required InvoiceModel invoiceModel}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          "Invoice Status",
          style: TextStyles.titleSmall,
        ),
        CustomDropdownButton(
          buttonWidth: 200,
          dropdownWidth: 200,
          applyTextScaleFactor: false,
          hint: "Choose Status",
          value: invoiceModel.invoiceStatus.isEmpty
              ? null
              : invoiceModel.invoiceStatus,
          dropdownItems: invoicesController.invoiceStatusList,
          onChanged: (value) {
            setInvoiceStatus(value!);
          },
        ),
      ],
    );
  }

  Widget _buildInvoiceRecurrenceDataWidget(
      {required InvoiceModel invoiceModel}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: CustomTwoElementsWrapWidget(
            firstWidget: InkWell(
              onTap: () {
                if (isEditEnabled) {
                  setState(() {
                    invoiceModel.isRecurring = !invoiceModel.isRecurring;
                  });
                }
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    (invoiceModel.isRecurring)
                        ? Icons.check_box_rounded
                        : Icons.check_box_outline_blank_rounded,
                    color: Theme.of(context).primaryColor,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    "Recurring Invoice",
                    style: TextStyles.bodyMedium,
                  ),
                ],
              ),
            ),
            secondWidget: InkWell(
              onTap: () {
                if (isEditEnabled) {
                  setState(() {
                    invoiceModel.isRecurring = !invoiceModel.isRecurring;
                  });
                }
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    (!invoiceModel.isRecurring)
                        ? Icons.check_box_rounded
                        : Icons.check_box_outline_blank_rounded,
                    color: Theme.of(context).primaryColor,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    "One-Time Invoice",
                    style: TextStyles.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (invoiceModel.isRecurring)
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: InkWell(
              onTap: () {
                if (!isEditEnabled || widget.isEdit) {
                  ShowSnackBar.error("Recurrence type can't be edited");
                }
              },
              child: CustomDropdownButton(
                buttonWidth: 200,
                dropdownWidth: 200,
                isDisabled: !isEditEnabled || widget.isEdit,
                validator: (value) => Validators.validateRequired(
                  value,
                  "Recurrence type",
                ),
                hint: "Recurrence type",
                dropdownItems:
                    RecurrenceType.values.map((e) => e.value).toList(),
                value: recurrenceType.value.isNotEmpty
                    ? recurrenceType.value
                    : null,
                onChanged: (value) => recurrenceType.value = value!,
              ),
            ),
          ),
        if (recurrenceType.value.isNotEmpty && invoiceModel.isRecurring)
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (!isRecurrenceStarted)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Start Date",
                        style: TextStyles.titleSmall,
                      ),
                      const SizedBox(height: 5),
                      InkWell(
                        onTap: () async {
                          if (isEditEnabled) {
                            DateTime formattedStartDate = DateTime.now();
                            String date =
                                await CustomDateTimeSelector.selectDate(
                              context: context,
                              passFirstDate: formattedStartDate,
                              initialDate: formattedStartDate,
                            );
                            recurrenceStartDate.value = date;
                            recurrenceStartDate.refresh();
                            recurrenceEndDate.value = "";
                            debugPrint("date::$date");
                          }
                        },
                        child: Container(
                          height: 45,
                          width: Get.width * 0.35,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Theme.of(context).colorScheme.tertiary,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.calendar_month_outlined,
                                  color: Theme.of(context).primaryColor,
                                  size: 20,
                                ),
                                const SizedBox(width: 5),
                                Expanded(
                                  child: Text(
                                    recurrenceStartDate.value,
                                    style: TextStyles.bodyMedium,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "End Date",
                      style: TextStyles.titleSmall,
                    ),
                    const SizedBox(height: 5),
                    InkWell(
                      onTap: () async {
                        if (isEditEnabled) {
                          var dateFormat = DateFormat('MM/dd/yyyy');
                          DateTime formattedStartDate =
                              DateTime.now().add(const Duration(days: 2));
                          if (!isRecurrenceStarted) {
                            if (recurrenceStartDate.value.isNotEmpty) {
                              formattedStartDate = dateFormat
                                  .parse(recurrenceStartDate.value)
                                  .add(const Duration(days: 2));
                            }
                          } else {
                            formattedStartDate =
                                DateTime.now().add(const Duration(days: 1));
                          }
                          String date = await CustomDateTimeSelector.selectDate(
                            context: context,
                            passFirstDate: formattedStartDate,
                            initialDate: formattedStartDate,
                          );
                          recurrenceEndDate.value = date;
                          recurrenceEndDate.refresh();
                          debugPrint("date::$date");
                        }
                      },
                      child: Container(
                        height: 45,
                        width: Get.width * 0.35,
                        decoration: BoxDecoration(
                          // color: CustomColor.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.tertiary,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Row(
                            children: [
                              Icon(
                                Icons.calendar_month_outlined,
                                color: Theme.of(context).primaryColor,
                                size: 20,
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  recurrenceEndDate.value,
                                  style: TextStyles.bodyMedium,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        if (checkShowCancelRecurringOption())
          Center(
            child: Column(
              children: [
                const SizedBox(height: 20),
                CustomButton(
                  text: "Cancel Recurrence",
                  function: () async {
                    if (isEditEnabled) {
                      showDialog(
                        context: context,
                        builder: (context) => DialogBox(
                          content: "Are you sure you want\nto Cancel?",
                          action2: "Ok",
                          action1: "Cancel",
                          function2: () async {
                            setState(() {
                              invoiceModel.isRecurring =
                                  !invoiceModel.isRecurring;
                            });
                            Loader.showLoader();
                            await saveInvoice();
                            Loader.hideLoader();
                            if (!Get.isSnackbarOpen) {
                              Get.back();
                            }
                          },
                          function1: () {
                            Get.back();
                          },
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          )
      ],
    );
  }

  Widget _buildNotesSectionWidget() {
    return Container(
      padding: const EdgeInsets.all(10),
      width: double.infinity,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [containerShadow(context)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Notes",
            style: TextStyles.titleMedium,
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: CustomTextField(
              hintText: "Notes",
              maxLines: null,
              isExpandable: true,
              controller: invoiceNotesController,
              onChange: (text) {
                invoicesController.currentInvoiceModel.value.notes = text;
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChooseMethodWidget() {
    return LayoutBuilder(builder: (context, constraints) {
      return Obx(
        () {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Payment Method",
                style: TextStyles.titleSmall,
              ),
              const SizedBox(width: 10),
              Container(
                //width: constraints.maxWidth * 0.7,
                //constraints: BoxConstraints(maxWidth: 255),
                padding: const EdgeInsets.only(top: 10),
                child: CustomDropdownButton(
                  searchable: true,
                  textEditingController: searchMethodsTextController,
                  buttonWidth: 200,
                  dropdownWidth: 200,
                  hint: "Choose Method",
                  dropdownItems: const [],
                  items: [
                    DropdownMenuItem<String>(
                      alignment: Alignment.topCenter,
                      value: "Add Method",
                      child: Container(
                        padding: EdgeInsets.zero,
                        alignment: Alignment.center,
                        child: FilledButton.icon(
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (context) => AddPaymentMethodDialog(),
                            );
                          },
                          icon: const Icon(Icons.add_circle_outline_outlined),
                          label: const Text("Add Method"),
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                      onTap: () {},
                    ),
                    ...invoicesController.workspaceDetailsController
                        .workspaceModel.value.paymentData.acceptedPaymentMethods
                        .map<DropdownMenuItem<String>>(
                      (method) {
                        return DropdownMenuItem<String>(
                          value: method,
                          child: Text(
                            method,
                            style: TextStyles.bodyMedium,
                          ),
                        );
                      },
                    ),
                  ],
                  value: null,
                  onChanged: (value) {
                    invoicesController.currentInvoiceModel.value.paymentMethod =
                        value!;
                  },
                ),
              ),
            ],
          );
        },
      );
    });
  }
}
