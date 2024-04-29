import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../../common/text_style.dart';
import '../../../controllers/invoices_controller.dart';
import '../../../model/invoice_model.dart';
import '../../../model/terms_conditions_model.dart';
import '../../../model/workspace_model.dart';
import '../../utils/pdf_viewer.dart';
import '../../widgets/billing_info_widget.dart';
import '../../widgets/container_shadow.dart';
import '../../widgets/custom_appbar.dart';
import '../../widgets/attachments_library_widget.dart';
import '../../widgets/preview_items_section_widget.dart';
import '../../widgets/preview_totals_section_widget.dart';
import '../../widgets/responsive_builder.dart';

class PreviewInvoiceScreen extends StatefulWidget {
  final TermsConditionsModel termsConditionsModel;
  const PreviewInvoiceScreen({
    required this.termsConditionsModel,
    super.key,
  });

  @override
  State<PreviewInvoiceScreen> createState() => _PreviewInvoiceScreenState();
}

class _PreviewInvoiceScreenState extends State<PreviewInvoiceScreen> {
  final InvoicesController invoicesController = Get.put(InvoicesController());
  String currencySymbol = "\$";
  InvoiceModel invoiceModel = InvoiceModel.empty();
  @override
  void initState() {
    currencySymbol = invoicesController
        .workspaceDetailsController.workspaceModel.value.currencyModel.symbol;
    invoiceModel = invoicesController.currentInvoiceModel.value;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: customAppBar(
        title: "Preview Invoice",
        context: context,
        isBack: true,
        showWebNavBar: false,
      ),
      body: Container(
        margin: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [containerShadow(context)],
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Invoice",
                style: TextStyles.titleMedium,
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    invoiceModel.invoiceName,
                    style: TextStyles.titleSmall,
                  ),
                  Text(
                    "Invoice # ${invoiceModel.invoiceNumber}",
                    style: TextStyles.titleSmall,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildDesktopBillingInfo(context),
              const SizedBox(height: 20),
              PreviewItemsSectionWidget(
                isEstimate: false,
                servicesList: invoiceModel.servicesList,
                currencySymbol: currencySymbol,
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: PreviewTotalsSectionWidget(
                  subTotal: invoiceModel.subTotal,
                  discount: invoiceModel.discountAmount,
                  tax: invoiceModel.taxAmount,
                  deposit: invoiceModel.depositAmount,
                  total: invoiceModel.total,
                  amount: invoiceModel.total - invoiceModel.depositAmount,
                  currencySymbol: currencySymbol,
                ),
              ),
              const SizedBox(height: 20),
              if (invoiceModel.attachments.isNotEmpty)
                AttachmentsLibraryWidget(
                  attachmentsList: (invoiceModel.attachments).obs,
                  onRemove: (index) {},
                  showDeleteIcon: false,
                ),
              if (widget.termsConditionsModel.id.isNotEmpty)
                const SizedBox(height: 20),
              if (widget.termsConditionsModel.id.isNotEmpty)
                _buildTermsConditions(),
              const SizedBox(height: 50),
              if (invoiceModel.footerTitle.isNotEmpty ||
                  invoiceModel.footerDescription.isNotEmpty)
                _buildFooter(),
            ],
          ),
        ),
      ),
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

  Widget _buildClientBillingInfoWidget({required InvoiceModel invoiceModel}) {
    return BillingInfoWidget(
      name: invoiceModel.clientFullName,
      email: invoiceModel.clientEmail,
      address: invoiceModel.clientAddress,
      phone: invoiceModel.clientPhone.internationalNumber,
      isWorkspace: false,
      isPreview: true,
    );
  }

  _buildDesktopBillingInfo(context) {
    return Obx(
      () {
        var workspaceModel =
            invoicesController.workspaceDetailsController.workspaceModel.value;
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
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: VerticalDivider(
                      color: Theme.of(context).dividerColor,
                      thickness: 1,
                      width: 1,
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        if (invoiceModel.clientId.isNotEmpty)
                          _buildClientBillingInfoWidget(
                              invoiceModel: invoiceModel),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTermsConditions() {
    var model = widget.termsConditionsModel;
    String url = "";
    if (model.attachments.isNotEmpty) {
      url = model.attachments[0].url;
    } else {
      url = model.termsConditionsPdfUrl;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Text(
          "Terms & Conditions",
          style: TextStyles.titleMedium,
        ),
        const SizedBox(height: 20),
        Text(
          model.title,
          style: TextStyles.titleSmall,
        ),
        const SizedBox(height: 10),
        if (url.isNotEmpty)
          InkWell(
            onTap: () {
              Get.to(() => ImagePdfViewerClass(url: url));
            },
            child: Container(
              height: 100.h,
              width: ResponsiveBuilder.isMobile(context) ? 90.w : 15.w,
              decoration: BoxDecoration(
                color: Theme.of(context).shadowColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.picture_as_pdf,
              ),
            ),
          ),
      ],
    );
  }

  _buildFooter() {
    return Column(
      children: [
        const Divider(),
        const SizedBox(height: 5),
        Text(
          invoicesController.currentInvoiceModel.value.footerTitle,
          style: TextStyles.titleSmall,
        ),
        const SizedBox(height: 5),
        Text(
          invoicesController.currentInvoiceModel.value.footerDescription,
          style: TextStyles.bodySmall,
        ),
      ],
    );
  }
}
