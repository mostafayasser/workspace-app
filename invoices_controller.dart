import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../common/constant.dart';
import '../model/attachment_model.dart';
import '../model/client_model.dart';
import '../model/cloud_functions/cancel_stripe_recurring_invoice_subscription_function_model.dart';
import '../model/cloud_functions/create_stripe_recurring_invoice_subscription_function_model.dart';
import '../model/cloud_functions/update_stripe_recurring_invoice_function_model.dart';
import '../model/cloud_functions/update_stripe_recurring_invoice_subscription_function_model.dart';
import '../model/estimate_model.dart';
import '../model/invoice_model.dart';
import '../model/invoice_package_model.dart';
import '../model/public_invoice_model.dart';
import '../model/selling_service_model.dart';
import '../model/storage_file_metadata_model.dart';
import '../model/storage_upload_metadata_model.dart';
import '../model/workspace_model.dart';
import '../services/cache_storage/cache_storage.dart';
import '../view/helpers/year_prefix.dart';
import '../view/widgets/snackbar.dart';
import 'auth_controller.dart';
import 'clients_controller.dart';
import 'email_automation_controller.dart';
import 'estimates_controller.dart';
import 'firebase_storage_controller.dart';
import 'services_controller.dart';
import 'workspace_details_controller.dart';

class InvoicesController extends GetxController {
  WorkspaceDetailsController workspaceDetailsController = Get.find();
  ClientsController clientsController = Get.put(ClientsController());
  EstimatesController estimatesController = Get.put(EstimatesController());
  ServicesController servicesController = Get.put(ServicesController());
  AuthController authController = Get.find();
  EmailAutomationController emailAutomationController =
      Get.put(EmailAutomationController());
  FirebaseStorageController firebaseStorageController =
      Get.put(FirebaseStorageController());
  //AnalyticsController analyticsController = Get.find();
  var searchController = TextEditingController().obs;
  final FirebaseFirestore fireStore = FirebaseFirestore.instance;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      invoicesStreamSubscription;
  RxBool isDataAvailable = false.obs;
  RxBool isLoading = false.obs;
  RxList<SellingServiceModel> allInvoiceServicesList =
      <SellingServiceModel>[].obs;

  TextEditingController serviceNameController = TextEditingController();
  TextEditingController editServiceDescriptionController =
      TextEditingController();
  TextEditingController editServiceAmountController = TextEditingController();

  Uint8List invoiceGeneratedPdf = Uint8List(0);
  DocumentSnapshot? lastClientInvoicesDocument;
  final List<String> paymentTermList = [
    "Due Upon Receipt",
    "1% 10 Net 30",
    "30 days",
  ];
  final List<String> invoiceStatusList = [
    AppConstant.pending,
    AppConstant.paid,
  ];
  Map<String, Color> invoiceStatusColorList = {
    AppConstant.pending: Colors.black45,
    AppConstant.paid: Colors.green,
  };

  RxString selectedStatusFilter = "".obs;
  List<String> sortByList = [
    AppConstant.dateDesc,
    AppConstant.dateAsc,
    AppConstant.totalDesc,
    AppConstant.totalAsc,
  ];
  RxString selectedSortBy = "".obs;

  RxList<InvoiceModel> invoicesList = <InvoiceModel>[].obs;
  RxList<InvoiceModel> searchInvoicesList = <InvoiceModel>[].obs;
  Rx<InvoiceModel> currentInvoiceModel = InvoiceModel.empty().obs;
  Rx<ClientModel> currentClientModel = ClientModel.empty().obs;
  EstimateModel currentInvoiceEstimateModel = EstimateModel.empty();
  Rx<Uint8List> pickedImage = Uint8List(0).obs;

  /// Invoice Footer
  Rx<TextEditingController> footerTitleController = TextEditingController().obs;
  Rx<TextEditingController> footerDescriptionController =
      TextEditingController().obs;

  @override
  void onClose() async {
    await invoicesStreamSubscription?.cancel();
    super.onClose();
  }

  Future<List<InvoiceModel>> getClientInvoices({
    required String clientId,
    required bool moreData,
    required bool viewPrices,
  }) async {
    String workspaceId =
        CacheStorageService.instance.read(AppConstant.workspaceId);
    List<InvoiceModel> invoices = [];
    if (!moreData) {
      lastClientInvoicesDocument = null;
    }
    QuerySnapshot<Map<String, dynamic>> query = !moreData
        ? await fireStore
            .collection(AppConstant.workspacesCollection)
            .doc(workspaceId)
            .collection(AppConstant.invoicesCollection)
            .where(AppConstant.clientId, isEqualTo: clientId)
            .orderBy(AppConstant.invoiceDate, descending: true)
            .limit(10)
            .get()
        : await fireStore
            .collection(AppConstant.workspacesCollection)
            .doc(workspaceId)
            .collection(AppConstant.invoicesCollection)
            .where(AppConstant.clientId, isEqualTo: clientId)
            .orderBy(AppConstant.invoiceDate, descending: true)
            .startAfterDocument(lastClientInvoicesDocument!)
            .limit(10)
            .get();
    invoices = query.docs.map((e) {
      var data = e.data();
      data[AppConstant.id] = e.id;
      return InvoiceModel.fromMap(
        data: data,
        includePrices: viewPrices,
      );
    }).toList();
    if (query.docs.isNotEmpty) {
      lastClientInvoicesDocument = query.docs.last;
    }
    return invoices;
  }

//TODO edit this function
  addPublicInvoiceData({
    required String invId,
    required String clientPhone,
    required String clientPhoneCountryCode,
    required String clientEmail,
    required String stripeLink,
    required Uint8List invoicePdfFileBytes,
    required Uint8List estimatePdfFileBytes,
    required bool isQuickInvoice,
  }) async {
    String workspaceId =
        CacheStorageService.instance.read(AppConstant.workspaceId);
    InvoiceModel? invoiceModel;
    EstimateModel? estimateModel;
    WorkspaceModel workspaceModel =
        estimatesController.workspaceDetailsController.workspaceModel.value;

    int invoiceIndex =
        invoicesList.indexWhere((element) => element.id == invId);
    if (invoiceIndex == -1) {
      await getInvoiceById(
        invId: invId,
        includeEstimatePrices: true,
        setAsCurrentInvoice: false,
      );
      invoiceIndex = invoicesList.indexWhere((element) => element.id == invId);
    }
    if (invoiceIndex != -1) {
      invoiceModel = invoicesList[invoiceIndex];
    } else {
      if (!isQuickInvoice) {
        int estIndex = estimatesController.estimatesList
            .indexWhere((element) => element.id == invId);
        if (estIndex == -1) {
          await estimatesController.getEstimateById(
            estId: invId,
            includeEstimatePrices: true,
          );
          estIndex = estimatesController.estimatesList
              .indexWhere((element) => element.id == invId);
        }
        if (estIndex != -1) {
          estimateModel = estimatesController.estimatesList[estIndex];
        }
      }
    }
    String invoicePdfUrl = "";
    String estimatePdfUrl = "";
    if (invoiceModel != null || estimateModel != null) {
      if (invoiceModel != null) {
        if (invoicePdfFileBytes.isNotEmpty) {
          String path = "$workspaceId/"
              "${AppConstant.invoices}/${invoiceModel.id}/pdf";
          String contentType = 'application/pdf';
          StorageUploadMetadataModel returnData =
              await firebaseStorageController.storageService.putData(
            bytes: invoicePdfFileBytes,
            path: path,
            contentType: contentType,
          );
          invoicePdfUrl = returnData.url;
        } else {
          invoicePdfUrl = invoiceModel.invoicePdfUrl;
        }
      }
      if (estimateModel != null) {
        if (estimatePdfFileBytes.isNotEmpty) {
          String path = "$workspaceId/"
              "${AppConstant.estimates}/${estimateModel.id}/pdf";
          String contentType = 'application/pdf';
          StorageUploadMetadataModel returnData =
              await firebaseStorageController.storageService.putData(
            bytes: estimatePdfFileBytes,
            path: path,
            contentType: contentType,
          );
          estimatePdfUrl = returnData.url;
          /* estimatesController.updateEstimatePdfLink(
            estId: estimateModel.id,
            url: estimatePdfUrl,
          ); */
        }
      }
      if (estimateModel != null) {
        if (estimatePdfUrl.isEmpty) {
          estimatePdfUrl = estimateModel.estimatePdfUrl;
        }
      }

      PublicInvoiceModel publicInvoiceModel = PublicInvoiceModel(
        id: invoiceModel?.id ?? estimateModel!.id,
        userId: "",
        workspaceId: workspaceId,
        status: "",
        invoiceNumber: -1,
        invoiceDate: invoiceModel?.invoiceDate ?? "",
        paymentTerm: invoiceModel?.paymentTerm ?? "",
        discountPer: invoiceModel?.discountPercentage.toStringAsFixed(2) ??
            estimateModel!.discountPercentage.toStringAsFixed(2),
        taxRatePer: invoiceModel?.taxPercentage.toStringAsFixed(2) ??
            estimateModel!.taxPercentage.toStringAsFixed(2),
        clientMessage: invoiceModel?.notes ?? "",
        paymentStatus: invoiceModel?.isPaid.toString() ?? AppConstant.pending,
        subTotal: invoiceModel?.subTotal.toStringAsFixed(2) ??
            estimateModel!.subTotal.toStringAsFixed(2),
        taxAmount: invoiceModel?.taxAmount.toStringAsFixed(2) ??
            estimateModel!.taxAmount.toStringAsFixed(2),
        discountAmount: invoiceModel?.discountAmount.toStringAsFixed(2) ??
            estimateModel!.discountAmount.toStringAsFixed(2),
        stripeMerchantId: workspaceModel.stripeData.stripeConnectAccountId,
        workspaceAddress: workspaceModel.locationData.address.formattedAddress,
        workspaceEmail: workspaceModel.info.email,
        workspaceName: workspaceModel.info.name,
        workspacePhone: workspaceModel.phoneModel.internationalNumber,
        workspaceImageUrl: workspaceModel.info.imageUrl,
        clientPhone: "+$clientPhoneCountryCode$clientPhone",
        clientAddress:
            invoiceModel?.clientAddress ?? estimateModel!.clientAddress,
        clientFullName:
            invoiceModel?.clientFullName ?? estimateModel!.clientFullName,
        clientEmail: clientEmail,
        invoiceDocuments: invoiceModel?.attachments ?? [],
        estimateDocuments: estimateModel?.attachments ?? [],
        estimateBottomImageDescriptions: [],
        estimateBottomImageUrls: [],
        estimateId: invoiceModel?.estimateId ?? estimateModel!.id,
        estimateNo: estimateModel?.estimateNumber.toString() ?? "",
        estimateType: invoiceModel?.estimateType ?? estimateModel!.estimateType,
        total: invoiceModel?.total.toStringAsFixed(2) ??
            estimateModel!.total.toStringAsFixed(2),
        depositPercentage: invoiceModel?.depositPercentage.toStringAsFixed(2) ??
            estimateModel!.depositPercentage.toStringAsFixed(2),
        depositAmount: invoiceModel?.depositAmount.toStringAsFixed(2) ??
            estimateModel!.depositAmount.toStringAsFixed(2),
        isDepositPaid:
            invoiceModel?.isDepositPaid ?? estimateModel!.isDepositPaid,
        currencyName: workspaceModel.currencyModel.code,
        currencySymbol: workspaceModel.currencyModel.symbol,
        serviceList: invoiceModel?.servicesList ??
            estimateModel!.servicesList
                .map((e) => SellingServiceModel(
                      serviceTotal: e.serviceTotal,
                      serviceDescription: e.serviceDescription,
                      serviceName: e.serviceName,
                      serviceImageUrl: e.serviceImageUrl,
                      serviceId: e.serviceId,
                      serviceIndustry: e.serviceIndustry,
                      servicePriceType: e.servicePriceType,
                      serviceUnitPrice: e.serviceUnitPrice,
                      serviceUnits: e.serviceUnits,
                      serviceNumber: e.serviceNumber,
                      serviceFlatRate: 0,
                    ))
                .toList(),
        packagesList: invoiceModel?.packagesList ??
            estimateModel!.packagesList
                .map((e) => InvoicePackageModel(
                      packageId: e.packageId,
                      packagePrice: e.packagePrice,
                      packageQuantity: e.packageQuantity,
                      packageTotal: e.packageTotal,
                      packageDescription: e.packageDescription,
                      packageName: e.packageName,
                      favorite: e.favorite,
                      packageImageUrl: e.networkImage,
                    ))
                .toList(),
        stripeLink: stripeLink,
        invoicePdfUrl: invoicePdfUrl,
        estimatePdfUrl: estimatePdfUrl,
        estimateFooterTitle:
            estimatesController.footerTitleController.value.text,
        estimateFooterDescription:
            estimatesController.footerDescriptionController.value.text,
        estimateTermsConditions:
            "", //   estimatesController.estimateTermsConditionsUrl.value,
        invoicePaymentTerms:
            invoiceModel != null && invoiceModel.invoicePaymentTerms.isNotEmpty
                ? invoiceModel.invoicePaymentTerms
                : workspaceModel.paymentData.paymentTerms,
        invoiceAcceptedPaymentMethods: invoiceModel != null &&
                invoiceModel.invoiceAcceptedPaymentMethods.isNotEmpty
            ? invoiceModel.invoiceAcceptedPaymentMethods
            : workspaceModel.paymentData.acceptedPaymentMethods.join(", "),
        stripeActiveSubscriptionId:
            invoiceModel?.stripeActiveSubscriptionId ?? "",
        stripeScheduleSubscriptionId:
            invoiceModel?.stripeScheduleSubscriptionId ?? "",
        stripePriceId: invoiceModel?.stripePriceId ?? "",
        stripeCustomerId: invoiceModel?.stripeCustomerId ?? "",
        stripeSubscriptionIntervalName:
            invoiceModel?.stripeSubscriptionIntervalName ?? "",
        stripeSubscriptionIntervalCount:
            invoiceModel?.stripeSubscriptionIntervalCount ?? 0,
        recurringInvoiceStartDateTimestamp:
            invoiceModel?.recurringInvoiceStartDateTimestamp ?? 0,
        recurringInvoiceEndDateTimestamp:
            invoiceModel?.recurringInvoiceEndDateTimestamp ?? 0,
        isRecurringInvoice: invoiceModel?.isRecurring ?? false,
        recurringInvoicePaymentLinksHistory: [],
        recurringInvoicesData: invoiceModel?.recurringInvoicesData ?? [],
        discountPercentageEnabled: invoiceModel?.discountPercentageEnabled ??
            estimateModel!.discountPercentageEnabled,
      );
      await fireStore
          .collection(AppConstant.publicInvoicesCollection)
          .doc(publicInvoiceModel.id)
          .set(publicInvoiceModel.toMap());
    }
  }

  markRecurringInvoiceAsPaidInsideMainReferenceInvoice(
      InvoiceModel model) async {
    String workspaceId =
        CacheStorageService.instance.read(AppConstant.workspaceId);
    if (model.recurrenceMainReferenceInvoiceDocId.isNotEmpty) {
      int index = invoicesList.indexWhere(
          (element) => element.id == model.recurrenceMainReferenceInvoiceDocId);
      if (index == -1) {
        await getInvoiceById(
          invId: model.recurrenceMainReferenceInvoiceDocId,
          includeEstimatePrices: true,
          setAsCurrentInvoice: false,
        );
        index = invoicesList.indexWhere((element) =>
            element.id == model.recurrenceMainReferenceInvoiceDocId);
      }
      if (index != -1) {
        for (var element in invoicesList[index].recurringInvoicesData) {
          if (element.newDocId == model.id) {
            element.paidAt = Timestamp.now().millisecondsSinceEpoch;
          }
        }
        invoicesList[index].updatedAt = Timestamp.now().millisecondsSinceEpoch;
        invoicesList[index].invoicePdfGenerationStatus = AppConstant.processing;
        invoicesList[index].invoicePdfUrl = "";
        await fireStore
            .collection(AppConstant.workspacesCollection)
            .doc(workspaceId)
            .collection(AppConstant.invoicesCollection)
            .doc(model.recurrenceMainReferenceInvoiceDocId)
            .update(invoicesList[index].toMap());
        /* analyticsController.increaseInvoiceTotal(
          services: invoicesList[index].servicesList,
          discountPercentage: invoicesList[index].discountPercentage,
          taxPercentage: invoicesList[index].taxPercentage,
          isQuickInvoice: invoicesList[index].estimateId.isEmpty,
          invoiceTotal: invoicesList[index].total,
        ); */
      }
    }
  }

  markRecurringInvoiceDocumentsAsPaid({
    required InvoiceModel model,
    required int paidAtTimestamp,
    required bool isQuickInvoice,
  }) async {
    String workspaceId =
        CacheStorageService.instance.read(AppConstant.workspaceId);
    for (int i = 0; i < model.recurringInvoicesData.length; i++) {
      if (model.recurringInvoicesData[i].paidAt == 0 ||
          model.recurringInvoicesData[i].paidAt == paidAtTimestamp) {
        var doc = await fireStore
            .collection(AppConstant.workspacesCollection)
            .doc(workspaceId)
            .collection(AppConstant.invoicesCollection)
            .doc(model.recurringInvoicesData[i].newDocId)
            .get();
        if (doc.exists) {
          int timestamp = Timestamp.now().millisecondsSinceEpoch;
          var invoiceModel = InvoiceModel.fromMap(
            data: doc.data()!,
            includePrices: true,
          );
          invoiceModel.invoiceStatus = AppConstant.paid;
          invoiceModel.updatedAt = timestamp;
          invoiceModel.paidAt = timestamp;
          invoiceModel.isPaid = true;
          invoiceModel.paidAmount = invoiceModel.total;
          invoiceModel.invoicePdfGenerationStatus = AppConstant.processing;
          invoiceModel.invoicePdfUrl = "";
          invoiceModel.paymentMethod = model.paymentMethod;
          doc.reference.update(invoiceModel.toMap());

          /* analyticsController.increaseInvoiceTotal(
            services: invoiceModel.servicesList,
            discountPercentage: model.discountPercentage,
            taxPercentage: model.taxPercentage,
            isQuickInvoice: isQuickInvoice,
            invoiceTotal: model.total,
          ); */
        }
      }
    }
  }

  Future deleteInvoice({
    bool isQuick = true,
    required String id,
  }) async {
    String workspaceId =
        CacheStorageService.instance.read(AppConstant.workspaceId);
    String estimateId = "";
    int invIndex = invoicesList.indexWhere((element) => element.id == id);
    if (invIndex != -1) {
      InvoiceModel invoice = invoicesList[invIndex];

      if (invoice.id == id) {
        for (var attachment in invoice.attachments) {
          if (attachment.path.isNotEmpty) {
            await deleteAttachment(attachment.path);
          }
        }
        estimateId = invoice.estimateId;
        if (invoice.recurrenceMainReferenceInvoiceDocId.isNotEmpty) {
          deleteRecurringInvoiceDataFromMainReference(
            recurringInvoiceId: id,
            recurringInvoiceStripeUrl: invoice.stripeInvoiceUrl,
            mainReferenceId: invoice.recurrenceMainReferenceInvoiceDocId,
          );
          /* if (invoice.isPaid) {
            analyticsController.decreaseInvoiceTotal(
              services: invoice.servicesList,
              discountPercentage: invoice.discountPercentage,
              taxPercentage: invoice.taxPercentage,
              isQuickInvoice: estimateId.isEmpty,
              invoiceDate: invoice.invoiceDate,
              invoiceTotal: invoice.total,
            );
          } */
        } else {
          if (invoice.isRecurring) {
            await deleteRecurringInvoiceDocuments(
              model: invoice,
              isQuickInvoice: estimateId.isEmpty,
            );
          } /* else {
            if (invoice.isPaid) {
              analyticsController.decreaseInvoiceTotal(
                services: invoice.servicesList,
                discountPercentage: invoice.discountPercentage,
                taxPercentage: invoice.taxPercentage,
                isQuickInvoice: estimateId.isEmpty,
                invoiceDate: invoice.invoiceDate,
                invoiceTotal: invoice.total,
              );
            }
          } */
          String stripeScheduleSubscriptionId =
              invoice.stripeScheduleSubscriptionId;
          int nowTimestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
          bool subscriptionIsOver =
              invoice.recurringInvoiceEndDateTimestamp < nowTimestamp;
          if (stripeScheduleSubscriptionId.isNotEmpty &&
              !invoice.isPaid &&
              !subscriptionIsOver) {
            await cancelRecurringInvoice(
              stripeAccountId: estimatesController
                  .workspaceDetailsController.stripeConnectAccountId.value,
              stripeScheduleSubscriptionId: stripeScheduleSubscriptionId,
            );
          }
        }
      }
    }
    await fireStore
        .collection(AppConstant.workspacesCollection)
        .doc(workspaceId)
        .collection(AppConstant.invoicesCollection)
        .doc(id)
        .delete();

    /* await fireStore
        .collection(AppConstant.publicInvoicesCollection)
        .doc(id)
        .delete(); */
  }

  deleteRecurringInvoiceDataFromMainReference({
    required String recurringInvoiceId,
    required String recurringInvoiceStripeUrl,
    required String mainReferenceId,
  }) async {
    String workspaceId =
        CacheStorageService.instance.read(AppConstant.workspaceId);
    int index =
        invoicesList.indexWhere((element) => element.id == mainReferenceId);
    if (index == -1) {
      await getInvoiceById(
        invId: mainReferenceId,
        includeEstimatePrices: true,
        setAsCurrentInvoice: false,
      );
      index =
          invoicesList.indexWhere((element) => element.id == mainReferenceId);
    }
    if (index != -1) {
      invoicesList[index]
          .recurringInvoicesData
          .removeWhere((element) => element.newDocId == recurringInvoiceId);
      await fireStore
          .collection(AppConstant.workspacesCollection)
          .doc(workspaceId)
          .collection(AppConstant.invoicesCollection)
          .doc(mainReferenceId)
          .update({
        AppConstant.recurringInvoicesData: invoicesList[index]
            .recurringInvoicesData
            .map((e) => e.toMap())
            .toList(),
      });
    }
  }

  deleteRecurringInvoiceDocuments({
    required InvoiceModel model,
    required bool isQuickInvoice,
  }) async {
    String workspaceId =
        CacheStorageService.instance.read(AppConstant.workspaceId);
    for (int i = 0; i < model.recurringInvoicesData.length; i++) {
      var doc = await fireStore
          .collection(AppConstant.workspacesCollection)
          .doc(workspaceId)
          .collection(AppConstant.invoicesCollection)
          .doc(model.recurringInvoicesData[i].newDocId)
          .get();
      if (doc.exists) {
        /* var invoice = InvoiceModel.fromMap(
          data: doc.data()!,
          includePrices: true,
        ); */
        await doc.reference.delete();
        /* if (invoice.isPaid) {
          await analyticsController.decreaseInvoiceTotal(
            services: invoice.servicesList,
            discountPercentage: invoice.discountPercentage,
            taxPercentage: invoice.taxPercentage,
            isQuickInvoice: isQuickInvoice,
            invoiceDate: invoice.invoiceDate,
            invoiceTotal: invoice.total,
          );
        } */
      }
    }
  }

  /*  updateInvoicePdfLink({required String invId, required String url}) async {
    String userId = CacheStorageService.instance.read(AppConstant.userId);
    String workspaceId =
        CacheStorageService.instance.read(AppConstant.workspaceId);
    await fireStore
        .collection(AppConstant.usersCollection)
        .doc(userId)
        .collection(AppConstant.workspaceInfoCollection)
        .doc(workspaceId)
        .collection(AppConstant.invoicesCollection)
        .doc(invId)
        .update({AppConstant.invoicePdfUrl: url});
    int index = invoicesList.indexWhere((element) => element.id == invId);
    if (index != -1) {
      invoicesList[index].invoicePdfUrl = url;
      invoicesList.refresh();
    }
    index = searchInvoicesList.indexWhere((element) => element.id == invId);
    if (index != -1) {
      searchInvoicesList[index].invoicePdfUrl = url;
      searchInvoicesList.refresh();
    }
  } */

  getInvoices({
    required bool hasData,
    required bool includePrices,
    VoidCallback? afterSorting,
  }) async {
    String workspaceId =
        CacheStorageService.instance.read(AppConstant.workspaceId);
    selectedSortBy.value = "";
    var snapshots = fireStore
        .collection(AppConstant.workspacesCollection)
        .doc(workspaceId)
        .collection(AppConstant.invoicesCollection)
        .orderBy(AppConstant.invoiceDate, descending: true)
        .snapshots();

    if (!hasData) {
      invoicesList.clear();
      searchInvoicesList.clear();
      await clientsController.getClientsData();
    }

    invoicesStreamSubscription = snapshots.listen(
      (event) {
        for (var document in event.docChanges) {
          if (document.doc.data() != null) {
            var doc = document.doc.data()!;
            doc[AppConstant.id] = document.doc.id;
            String name = "";
            String email = "";
            for (var clientElement in clientsController.clientsData) {
              if (document.doc.data()![AppConstant.clientId] ==
                  clientElement.id) {
                name = clientElement.fullName;
                email = clientElement.emails.first.email;
              }
            }

            doc[AppConstant.clientFullName] = name;
            doc[AppConstant.email] = email;
            int index;
            index = invoicesList
                .indexWhere((invoice) => invoice.id == document.doc.id);
            if (index != -1) {
              if (document.newIndex != -1) {
                debugPrint(doc[AppConstant.invoiceNumber].toString());
                invoicesList[index] = InvoiceModel.fromMap(
                  data: doc,
                  includePrices: includePrices,
                );
                index = searchInvoicesList
                    .indexWhere((invoice) => invoice.id == document.doc.id);
                if (index != -1) {
                  searchInvoicesList[index] = InvoiceModel.fromMap(
                    data: doc,
                    includePrices: includePrices,
                  );
                }
              } else {
                invoicesList
                    .removeWhere((element) => element.id == document.doc.id);
                searchInvoicesList
                    .removeWhere((element) => element.id == document.doc.id);
              }
            } else {
              if (document.newIndex != -1) {
                invoicesList.add(InvoiceModel.fromMap(
                  data: doc,
                  includePrices: includePrices,
                ));
                searchInvoicesList.add(InvoiceModel.fromMap(
                  data: doc,
                  includePrices: includePrices,
                ));
              }
            }
          }
        }
        invoicesList.value = invoicesList.toSet().toList();
        searchInvoicesList.value = searchInvoicesList.toSet().toList();
        sortInvoiceList();
        if (afterSorting != null) {
          afterSorting();
        }
        isDataAvailable.value = true;
        isLoading.value = false;
      },
      onDone: () => invoicesStreamSubscription?.cancel() ?? () {},
      onError: (error) {
        invoicesStreamSubscription?.cancel() ?? () {};
      },
    );
  }

  sortInvoiceList() {
    searchInvoicesList.clear();
    if (selectedSortBy.value == AppConstant.dateDesc ||
        selectedSortBy.value == AppConstant.dateAsc ||
        selectedSortBy.value.isEmpty) {
      invoicesList.sort((a, b) {
        var ascSortingCondition = a.createdAt - b.createdAt;
        var descSortingCondition = b.createdAt - a.createdAt;
        return selectedSortBy.value == AppConstant.dateDesc ||
                selectedSortBy.value.isEmpty
            ? descSortingCondition
            : ascSortingCondition;
      });
    } else if (selectedSortBy.value == AppConstant.totalDesc ||
        selectedSortBy.value == AppConstant.totalAsc) {
      invoicesList.sort((a, b) {
        var ascSortingCondition = (a.total - b.total).toInt();
        var descSortingCondition = (b.total - a.total).toInt();
        return selectedSortBy.value == AppConstant.totalDesc
            ? descSortingCondition
            : ascSortingCondition;
      });
    }
    for (var element in invoicesList) {
      searchInvoicesList.add(
        InvoiceModel.fromMap(
          data: element.toMap(),
          includePrices: true,
        ),
      );
    }
    invoicesList.refresh();
    searchInvoicesList.refresh();
  }

  getInvoiceById({
    required String invId,
    required bool includeEstimatePrices,
    required bool setAsCurrentInvoice,
  }) async {
    if (setAsCurrentInvoice) {
      currentInvoiceModel.value = InvoiceModel.empty();
    }
    int index = invoicesList.indexWhere((element) => element.id == invId);
    if (index != -1) {
      if (setAsCurrentInvoice) {
        currentInvoiceModel.value = InvoiceModel.fromMap(
          data: invoicesList[index].toMap(),
          includePrices: includeEstimatePrices,
        );
      }
    } else {
      String workspaceId =
          CacheStorageService.instance.read(AppConstant.workspaceId);
      var data = await fireStore
          .collection(AppConstant.workspacesCollection)
          .doc(workspaceId)
          .collection(AppConstant.invoicesCollection)
          .doc(invId)
          .get();
      if (data.exists) {
        var doc = data.data()!;
        var invModel = InvoiceModel.fromMap(
          data: doc,
          includePrices: includeEstimatePrices,
        );
        invoicesList.add(invModel);
        searchInvoicesList.add(invModel);
        if (setAsCurrentInvoice) {
          currentInvoiceModel.value = InvoiceModel.fromMap(
            data: doc,
            includePrices: includeEstimatePrices,
          );
        }
      }
    }
  }

  Future<Map<String, dynamic>> createRecurringInvoice({
    required double invoiceTotal,
    required String currencyCode,
    required String intervalName,
    required int intervalCount,
    required String stripeCustomerId,
    required String clientName,
    required String stripeAccountId,
    required String invId,
    required int recurringInvoiceStartTimestamp,
    required int recurringInvoiceEndTimestamp,
  }) async {
    String workspaceId =
        CacheStorageService.instance.read(AppConstant.workspaceId);
    var callable = FirebaseFunctions.instance.httpsCallable(
      AppConstant.createStripeRecurringInvoiceSubscription,
      options: HttpsCallableOptions(
        timeout: const Duration(seconds: 10),
      ),
    );
    try {
      final result = await callable
          .call(CreateStripeRecurringInvoiceSubscriptionFunctionModel(
        userId: authController.userModel.id,
        amount: invoiceTotal,
        currencyCode: currencyCode,
        interval: intervalName,
        intervalCount: intervalCount,
        stripeCustomerId: stripeCustomerId,
        clientFullName: clientName,
        stripeAccountId: stripeAccountId,
        workspaceId: workspaceId,
        invoiceId: invId,
        startDateTimestamp: recurringInvoiceStartTimestamp,
        endDateTimestamp: recurringInvoiceEndTimestamp,
      ).toMap());
      log("response... ${jsonEncode(result.data)}");
      if (result.data["statusCode"] == 200) {
        return {
          AppConstant.stripeScheduleSubscriptionId: result.data["data"]
              [AppConstant.stripeScheduleSubscriptionId],
          AppConstant.stripeActiveSubscriptionId: result.data["data"]
              [AppConstant.stripeActiveSubscriptionId],
          AppConstant.stripePriceId: result.data["data"]
              [AppConstant.stripePriceId],
        };
      } else {
        ShowSnackBar.error(result.data["message"]);
        return {};
      }
    } catch (e) {
      ShowSnackBar.error("An error occurred");
      debugPrint("##### ${e.toString()}");
      return {};
    }
  }

  Future<Map<String, dynamic>> updateRecurringInvoiceSubscription({
    required String invId,
    required double invoiceTotal,
    required String currencyCode,
    required String intervalName,
    required int intervalCount,
    required String customerStripeId,
    required String clientName,
    required String stripeAccountId,
    required String stripeScheduleSubscriptionId,
    required int recurringInvoiceStartTimestamp,
    required int recurringInvoiceEndTimestamp,
  }) async {
    String workspaceId =
        CacheStorageService.instance.read(AppConstant.workspaceId);
    var callable = FirebaseFunctions.instance.httpsCallable(
      AppConstant.updateStripeRecurringInvoiceSubscription,
      options: HttpsCallableOptions(
        timeout: const Duration(seconds: 10),
      ),
    );
    try {
      final result = await callable
          .call(UpdateStripeRecurringInvoiceSubscriptionFunctionModel(
        userId: authController.userModel.id,
        workspaceId: workspaceId,
        invoiceId: invId,
        amount: invoiceTotal,
        currencyCode: currencyCode,
        interval: intervalName,
        intervalCount: intervalCount,
        stripeCustomerId: customerStripeId,
        clientFullName: clientName,
        stripeAccountId: stripeAccountId,
        stripeScheduleSubscriptionId: stripeScheduleSubscriptionId,
        startDateTimestamp: recurringInvoiceStartTimestamp,
        endDateTimestamp: recurringInvoiceEndTimestamp,
      ).toMap());

      log("response... ${jsonEncode(result.data)}");
      if (result.data["statusCode"] == 200) {
        return {
          AppConstant.stripeScheduleSubscriptionId: result.data["data"]
              [AppConstant.stripeScheduleSubscriptionId],
          AppConstant.stripePriceId: result.data["data"]
              [AppConstant.stripePriceId],
        };
      } else {
        ShowSnackBar.error(result.data["message"]);
        return {};
      }
    } catch (e) {
      ShowSnackBar.error("An error occurred");
      debugPrint("##### ${e.toString()}");
      return {};
    }
  }

  Future<Map<String, dynamic>> updateRecurringInvoice({
    required String mainInvoiceId,
    required String recurringInvoiceId,
    required double newInvoiceTotal,
    required double oldInvoiceTotal,
    required String currencyCode,
    required String intervalName,
    required int intervalCount,
    required String customerStripeId,
    required String clientName,
    required String stripeAccountId,
    required String stripeScheduleSubscriptionId,
    required String stripeActiveSubscriptionId,
    required String stripeInvoiceId,
    required int recurringInvoiceStartTimestamp,
    required int recurringInvoiceEndTimestamp,
  }) async {
    String workspaceId =
        CacheStorageService.instance.read(AppConstant.workspaceId);
    var callable = FirebaseFunctions.instance.httpsCallable(
      AppConstant.updateStripeRecurringInvoice,
      options: HttpsCallableOptions(
        timeout: const Duration(seconds: 10),
      ),
    );
    try {
      var functionModel = UpdateStripeRecurringInvoiceFunctionModel(
        userId: authController.userModel.id,
        workspaceId: workspaceId,
        mainInvoiceId: mainInvoiceId,
        recurringInvoiceId: recurringInvoiceId,
        recurringInvoiceAmount: newInvoiceTotal,
        mainInvoiceAmount: oldInvoiceTotal,
        currencyCode: currencyCode,
        interval: intervalName,
        intervalCount: intervalCount,
        stripeCustomerId: customerStripeId,
        clientFullName: clientName,
        stripeAccountId: stripeAccountId,
        stripeScheduleSubscriptionId: stripeScheduleSubscriptionId,
        startDateTimestamp: recurringInvoiceStartTimestamp,
        endDateTimestamp: recurringInvoiceEndTimestamp,
        stripeActiveSubscriptionId: stripeActiveSubscriptionId,
        stripeInvoiceId: stripeInvoiceId,
      );
      final result = await callable.call(functionModel.toMap());

      log("response... ${jsonEncode(result.data)}");
      if (result.data["statusCode"] == 200) {
        return {
          AppConstant.stripeScheduleSubscriptionId: result.data["data"]
              [AppConstant.stripeScheduleSubscriptionId],
          AppConstant.stripePriceId: result.data["data"]
              [AppConstant.stripePriceId],
          AppConstant.stripeInvoiceId: result.data["data"]
              [AppConstant.stripeInvoiceId],
          AppConstant.stripeInvoiceUrl: result.data["data"]
              [AppConstant.stripeInvoiceUrl],
        };
      } else {
        ShowSnackBar.error(result.data["message"]);
        return {};
      }
    } catch (e) {
      ShowSnackBar.error("An error occurred");
      debugPrint("##### ${e.toString()}");
      return {};
    }
  }

  Future<bool> cancelRecurringInvoice({
    required String stripeAccountId,
    required String stripeScheduleSubscriptionId,
  }) async {
    var callable = FirebaseFunctions.instance.httpsCallable(
      AppConstant.cancelStripeRecurringInvoiceSubscription,
      options: HttpsCallableOptions(
        timeout: const Duration(seconds: 10),
      ),
    );
    try {
      final result = await callable
          .call(CancelStripeRecurringInvoiceSubscriptionFunctionModel(
        stripeAccountId: stripeAccountId,
        stripeScheduleSubscriptionId: stripeScheduleSubscriptionId,
      ).toMap());

      log("response... ${jsonEncode(result.data)}");
      if (result.data["statusCode"] == 200) {
        return true;
      } else {
        ShowSnackBar.error(result.data["message"]);
        return false;
      }
    } catch (e) {
      ShowSnackBar.error("An error occurred");
      debugPrint("##### ${e.toString()}");
      return false;
    }
  }

  setClientData(String name) {
    for (var client in clientsController.clientsData) {
      if (client.fullName == name) {
        currentClientModel.value = client;
        currentInvoiceModel.value.clientId = client.id;
        currentInvoiceModel.value.clientFullName = client.fullName;
        currentInvoiceModel.value.clientLeadSource = client.leadSource;
        currentInvoiceModel.value.clientCompanyName = client.companyName;
        for (var address in currentClientModel.value.addresses) {
          if (address.isPrimary) {
            currentInvoiceModel.value.clientAddress = address.formattedAddress;
            currentInvoiceModel.value.clientAddressId = address.placeId;
            currentInvoiceModel.value.clientAddressLatitude = address.latitude;
            currentInvoiceModel.value.clientAddressLongitude =
                address.longitude;
          }
        }
        for (var email in currentClientModel.value.emails) {
          if (email.isPrimary) {
            currentInvoiceModel.value.clientEmail = email.email;
          }
        }
        for (var phone in currentClientModel.value.phoneNumbers) {
          if (phone.isPrimary) {
            currentInvoiceModel.value.clientPhone = phone;
          }
        }
      }
    }
    currentInvoiceModel.refresh();
  }

  setClientDataFromEstimateModel({required EstimateModel estimateModel}) {
    String clientFullName = estimateModel.clientFullName;
    int index = clientsController.clientsData
        .indexWhere((element) => element.id == estimateModel.clientId);
    if (index == -1) return;
    var client = clientsController.clientsData[index];
    if (client.fullName != estimateModel.clientFullName) {
      clientFullName = client.fullName;
    }
    currentInvoiceModel.value.clientId = currentInvoiceEstimateModel.clientId;
    currentInvoiceModel.value.clientFullName = clientFullName;
    currentInvoiceModel.value.clientCompanyName =
        currentInvoiceEstimateModel.clientCompanyName;
    currentInvoiceModel.value.clientLeadSource =
        currentInvoiceEstimateModel.clientLeadSource;
    currentInvoiceModel.value.clientAddress =
        currentInvoiceEstimateModel.clientAddress;
    currentInvoiceModel.value.clientAddressId =
        currentInvoiceEstimateModel.clientAddressId;
    currentInvoiceModel.value.clientAddressLatitude =
        currentInvoiceEstimateModel.clientAddressLatitude;
    currentInvoiceModel.value.clientAddressLongitude =
        currentInvoiceEstimateModel.clientAddressLongitude;
    currentInvoiceModel.value.clientEmail =
        currentInvoiceEstimateModel.clientEmail;
    currentInvoiceModel.value.clientPhone =
        currentInvoiceEstimateModel.clientPhone;
    currentInvoiceModel.refresh();
  }

  setClientAddress(String address) {
    for (var element in currentClientModel.value.addresses) {
      if (element.formattedAddress == address) {
        currentInvoiceModel.value.clientAddress = element.formattedAddress;
        currentInvoiceModel.value.clientAddressId = element.placeId;
        currentInvoiceModel.value.clientAddressLatitude = element.latitude;
        currentInvoiceModel.value.clientAddressLongitude = element.longitude;
      }
    }
    currentInvoiceModel.refresh();
  }

  setClientEmail(String email) {
    for (var element in currentClientModel.value.emails) {
      if (element.email == email) {
        currentInvoiceModel.value.clientEmail = element.email;
      }
    }
    currentInvoiceModel.refresh();
  }

  setClientPhone(String phone) {
    for (var element in currentClientModel.value.phoneNumbers) {
      if (element.internationalNumber == phone) {
        currentInvoiceModel.value.clientPhone = element;
      }
    }
    currentInvoiceModel.refresh();
  }

  updateWorkspaceInvNo(String newNum) async {
    String workspaceId =
        CacheStorageService.instance.read(AppConstant.workspaceId);
    workspaceDetailsController.workspaceModel.value.invoiceData.number = newNum;
    await fireStore
        .collection(AppConstant.workspacesCollection)
        .doc(workspaceId)
        .update(workspaceDetailsController.workspaceModel.value.toMap());
  }

  Future<String> isValidStripeData() async {
    String errorMessage = "";
    if (workspaceDetailsController.stripeConnectAccountId.value.isEmpty) {
      errorMessage =
          "Please complete your bank information to create recurring invoices.";
      return errorMessage;
    }
    if (currentInvoiceModel.value.clientEmail.isEmpty) {
      errorMessage =
          "Please add email to client in order to set up recurring invoices";
      return errorMessage;
    }
    if (currentClientModel.value.stripeConnectAccountCustomerId.isEmpty) {
      var stripeData = await clientsController.addClientToStripeConnectAccount(
        clientId: currentClientModel.value.id,
        isUpdate: true,
        clientName: currentClientModel.value.fullName,
        clientEmail: currentInvoiceModel.value.clientEmail,
        clientPhone: currentInvoiceModel.value.clientPhone.internationalNumber,
        stripeConnectAccountId: workspaceDetailsController
            .workspaceModel.value.stripeData.stripeConnectAccountId,
      );
      if (stripeData.isNotEmpty) {
        currentClientModel.value.stripeConnectAccountCustomerId =
            stripeData[AppConstant.stripeConnectAccountClientId];
        currentInvoiceModel.value.stripeCustomerId =
            stripeData[AppConstant.stripeConnectAccountClientId];
      } else {
        errorMessage = "Failed to add client to stripe account";
        return errorMessage;
      }
    }
    return errorMessage;
  }

  String isValidRecurrenceData({
    required bool isRecurrenceStarted,
    required String recurrenceType,
    required String recurrenceStartDate,
    required String recurrenceEndDate,
  }) {
    String errorMessage = "";
    if (!isRecurrenceStarted && recurrenceStartDate.isEmpty) {
      errorMessage = "Please select recurrence start date";
      return errorMessage;
    }
    if (recurrenceEndDate.isEmpty) {
      errorMessage = "Please select recurrence end date";
      return errorMessage;
    }
    var dateFormat = DateFormat('MM/dd/yyyy');
    var startDate = dateFormat.parse(recurrenceStartDate);
    var endDate = dateFormat.parse(recurrenceEndDate);
    int differenceInDays = endDate.difference(startDate).inDays;
    if (differenceInDays < 7 && recurrenceType == AppConstant.everyWeek) {
      errorMessage =
          "Recurrence end date should be at least 7 days after start date";
      return errorMessage;
    } else if (differenceInDays < 14 &&
        recurrenceType == AppConstant.everyTwoWeeks) {
      errorMessage =
          "Recurrence end date should be at least 14 days after start date";
      return errorMessage;
    } else if (differenceInDays < 31 &&
        recurrenceType == AppConstant.everyMonth) {
      errorMessage =
          "Recurrence end date should be at least 30 days after start date";
      return errorMessage;
    } else if (differenceInDays < 365 &&
        recurrenceType == AppConstant.everyYear) {
      errorMessage =
          "Recurrence end date should be at least 365 days after start date";
      return errorMessage;
    }
    return errorMessage;
  }

  setInvoiceRecurrenceDataForSave({
    required bool isRecurrenceStarted,
    required String recurrenceType,
    required String recurrenceStartDate,
    required String recurrenceEndDate,
  }) async {
    InvoiceModel invoiceModel = currentInvoiceModel.value;
    invoiceModel.stripeCustomerId =
        currentClientModel.value.stripeConnectAccountCustomerId;
    var dateFormat = DateFormat('MM/dd/yyyy');
    var now = DateTime.now();
    if (!isRecurrenceStarted) {
      var formattedStartDate = dateFormat.parse(recurrenceStartDate);
      var startDate = DateTime(
        formattedStartDate.year,
        formattedStartDate.month,
        formattedStartDate.day,
        now.hour,
        now.minute,
        now.second,
      );
      invoiceModel.recurringInvoiceStartDateTimestamp =
          startDate.millisecondsSinceEpoch ~/ 1000;
    }
    var formattedEndDate = dateFormat.parse(recurrenceEndDate);
    var endDate = DateTime(
      formattedEndDate.year,
      formattedEndDate.month,
      formattedEndDate.day,
      now.hour + 1,
      now.minute,
      now.second,
    );
    invoiceModel.recurringInvoiceEndDateTimestamp =
        endDate.millisecondsSinceEpoch ~/ 1000;

    String formattedRecurrenceType = formatReccurenceTypeToIntervalName(
      recurrenceType,
    );
    if (formattedRecurrenceType == "biweek") {
      invoiceModel.stripeSubscriptionIntervalName = "week";
      invoiceModel.stripeSubscriptionIntervalCount = 2;
    } else {
      invoiceModel.stripeSubscriptionIntervalName = formattedRecurrenceType;
      invoiceModel.stripeSubscriptionIntervalCount = 1;
    }
    if (invoiceModel.stripeScheduleSubscriptionId.isEmpty) {
      var recurringInvoiceDataMap = await createRecurringInvoice(
        invoiceTotal: invoiceModel.total,
        currencyCode: workspaceDetailsController
            .workspaceModel.value.currencyModel.code
            .toLowerCase(),
        intervalName: invoiceModel.stripeSubscriptionIntervalName,
        intervalCount: invoiceModel.stripeSubscriptionIntervalCount,
        stripeCustomerId: invoiceModel.stripeCustomerId,
        clientName: invoiceModel.clientFullName,
        stripeAccountId:
            workspaceDetailsController.stripeConnectAccountId.value,
        invId: invoiceModel.id,
        recurringInvoiceStartTimestamp:
            invoiceModel.recurringInvoiceStartDateTimestamp,
        recurringInvoiceEndTimestamp:
            invoiceModel.recurringInvoiceEndDateTimestamp,
      );
      if (recurringInvoiceDataMap.isNotEmpty) {
        invoiceModel.stripeScheduleSubscriptionId =
            recurringInvoiceDataMap[AppConstant.stripeScheduleSubscriptionId];
        invoiceModel.stripeActiveSubscriptionId =
            recurringInvoiceDataMap[AppConstant.stripeActiveSubscriptionId];
        invoiceModel.stripePriceId =
            recurringInvoiceDataMap[AppConstant.stripePriceId];
      } else {
        clearInvoiceRecurrenceData();
        invoiceModel = currentInvoiceModel.value;
      }
    } else {
      var nowTimestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if (nowTimestamp < invoiceModel.recurringInvoiceEndDateTimestamp) {
        if (invoiceModel.recurrenceMainReferenceInvoiceDocId.isEmpty) {
          var recurringInvoiceDataMap =
              await updateRecurringInvoiceSubscription(
            invId: invoiceModel.id,
            invoiceTotal: invoiceModel.total,
            currencyCode: workspaceDetailsController
                .workspaceModel.value.currencyModel.code
                .toLowerCase(),
            intervalName: invoiceModel.stripeSubscriptionIntervalName,
            intervalCount: invoiceModel.stripeSubscriptionIntervalCount,
            customerStripeId: invoiceModel.stripeCustomerId,
            clientName: invoiceModel.clientFullName,
            stripeAccountId:
                workspaceDetailsController.stripeConnectAccountId.value,
            stripeScheduleSubscriptionId:
                invoiceModel.stripeScheduleSubscriptionId,
            recurringInvoiceStartTimestamp:
                invoiceModel.recurringInvoiceStartDateTimestamp,
            recurringInvoiceEndTimestamp:
                invoiceModel.recurringInvoiceEndDateTimestamp,
          );
          if (recurringInvoiceDataMap.isNotEmpty) {
            invoiceModel.stripeScheduleSubscriptionId = recurringInvoiceDataMap[
                AppConstant.stripeScheduleSubscriptionId];
            invoiceModel.stripePriceId =
                recurringInvoiceDataMap[AppConstant.stripePriceId];
          }
        } else {
          double mainInvoiceTotal = 0, oldInvoiceTotal = 0;
          int recurringInvoiceStartTimestamp =
              invoiceModel.recurringInvoiceStartDateTimestamp;
          int recurringInvoiceEndTimestamp =
              invoiceModel.recurringInvoiceEndDateTimestamp;
          int recurringInvoiceIndex = invoicesList
              .indexWhere((element) => element.id == invoiceModel.id);
          if (recurringInvoiceIndex != -1) {
            oldInvoiceTotal = invoicesList[recurringInvoiceIndex].total;
            int mainReferenceIndex = invoicesList.indexWhere((element) =>
                element.id ==
                invoicesList[recurringInvoiceIndex]
                    .recurrenceMainReferenceInvoiceDocId);
            if (mainReferenceIndex != -1) {
              mainInvoiceTotal = invoicesList[mainReferenceIndex].total;
              recurringInvoiceStartTimestamp = invoicesList[mainReferenceIndex]
                  .recurringInvoiceStartDateTimestamp;
              recurringInvoiceEndTimestamp = invoicesList[mainReferenceIndex]
                  .recurringInvoiceEndDateTimestamp;
            }
          }
          if (oldInvoiceTotal != invoiceModel.total && mainInvoiceTotal != 0) {
            var recurringInvoiceDataMap = await updateRecurringInvoice(
              mainInvoiceId: invoiceModel.recurrenceMainReferenceInvoiceDocId,
              recurringInvoiceId: invoiceModel.id,
              newInvoiceTotal: invoiceModel.total,
              oldInvoiceTotal: mainInvoiceTotal,
              currencyCode: workspaceDetailsController
                  .workspaceModel.value.currencyModel.code
                  .toLowerCase(),
              intervalName: invoiceModel.stripeSubscriptionIntervalName,
              intervalCount: invoiceModel.stripeSubscriptionIntervalCount,
              customerStripeId: invoiceModel.stripeCustomerId,
              clientName: invoiceModel.clientFullName,
              stripeAccountId:
                  workspaceDetailsController.stripeConnectAccountId.value,
              stripeScheduleSubscriptionId:
                  invoiceModel.stripeScheduleSubscriptionId,
              stripeActiveSubscriptionId:
                  invoiceModel.stripeActiveSubscriptionId,
              stripeInvoiceId: invoiceModel.stripeInvoiceId,
              recurringInvoiceStartTimestamp: recurringInvoiceStartTimestamp,
              recurringInvoiceEndTimestamp: recurringInvoiceEndTimestamp,
            );
            if (recurringInvoiceDataMap.isNotEmpty) {
              invoiceModel.stripeScheduleSubscriptionId =
                  recurringInvoiceDataMap[
                      AppConstant.stripeScheduleSubscriptionId];
              invoiceModel.stripePriceId =
                  recurringInvoiceDataMap[AppConstant.stripePriceId];
              invoiceModel.stripeInvoiceId =
                  recurringInvoiceDataMap[AppConstant.stripeInvoiceId];
              invoiceModel.stripeInvoiceUrl =
                  recurringInvoiceDataMap[AppConstant.stripeInvoiceUrl];
            }
          }
        }
      }
    }
    currentInvoiceModel.value = invoiceModel;
  }

  checkForCancelingRecurringInvoice({required bool isEditEnabled}) async {
    InvoiceModel invoiceModel = currentInvoiceModel.value;
    int nowTimestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    bool subscriptionIsOver =
        invoiceModel.recurringInvoiceEndDateTimestamp < nowTimestamp;
    if (invoiceModel.stripeScheduleSubscriptionId.isNotEmpty &&
        isEditEnabled &&
        !subscriptionIsOver) {
      var canceled = await cancelRecurringInvoice(
        stripeAccountId:
            workspaceDetailsController.stripeConnectAccountId.value,
        stripeScheduleSubscriptionId: invoiceModel.stripeScheduleSubscriptionId,
      );
      if (canceled) {
        clearInvoiceRecurrenceData();
      }
    }
  }

  clearInvoiceRecurrenceData() {
    InvoiceModel invoiceModel = currentInvoiceModel.value;
    invoiceModel.stripeScheduleSubscriptionId = "";
    invoiceModel.stripeActiveSubscriptionId = "";
    invoiceModel.stripePriceId = "";
    invoiceModel.stripeSubscriptionIntervalName = "";
    invoiceModel.stripeSubscriptionIntervalCount = 0;
    invoiceModel.recurringInvoiceStartDateTimestamp = 0;
    invoiceModel.recurringInvoiceEndDateTimestamp = 0;
    currentInvoiceModel.value = invoiceModel;
  }

  createInvoiceDoc() async {
    String workspaceId =
        CacheStorageService.instance.read(AppConstant.workspaceId);
    var doc = fireStore
        .collection(AppConstant.workspacesCollection)
        .doc(workspaceId)
        .collection(AppConstant.invoicesCollection)
        .doc();
    currentInvoiceModel.value.id = doc.id;
  }

  handlePaidRecurringInvoice({required int paidAtTimestamp}) async {
    if (currentInvoiceModel.value.recurrenceMainReferenceInvoiceDocId.isEmpty) {
      await markRecurringInvoiceDocumentsAsPaid(
        model: currentInvoiceModel.value,
        paidAtTimestamp: paidAtTimestamp,
        isQuickInvoice: currentInvoiceModel.value.estimateId.isEmpty,
      );
      for (var element in currentInvoiceModel.value.recurringInvoicesData) {
        element.paidAt = paidAtTimestamp;
      }
    } else {
      await markRecurringInvoiceAsPaidInsideMainReferenceInvoice(
          currentInvoiceModel.value);
    }
  }

  saveInvoiceData({
    required bool isEdit,
    required bool isEstimateInvoice,
  }) async {
    String workspaceId =
        CacheStorageService.instance.read(AppConstant.workspaceId);
    /* String userId = CacheStorageService.instance.read(AppConstant.userId);
    String stripeConnectAccountId = workspaceDetailsController
        .workspaceModel.value.stripeData.stripeConnectAccountId; */
    int paidAtTimestamp = Timestamp.now().millisecondsSinceEpoch;
    var doc = fireStore
        .collection(AppConstant.workspacesCollection)
        .doc(workspaceId)
        .collection(AppConstant.invoicesCollection)
        .doc(currentInvoiceModel.value.id);
    await uploadInvoiceDocuments(isEdit: isEdit);
    bool isPaid = currentInvoiceModel.value.invoiceStatus == AppConstant.paid;
    if (isPaid) {
      setPaidInvoiceFields(paidAtTimestamp: paidAtTimestamp);
      if (currentInvoiceModel.value.isRecurring) {
        handlePaidRecurringInvoice(paidAtTimestamp: paidAtTimestamp);
      }
    } /* else if (!currentInvoiceModel.value.isRecurring &&
        stripeConnectAccountId.isNotEmpty) {
      var callable = FirebaseFunctions.instance.httpsCallable(
        AppConstant.createStripeCheckout,
        options: HttpsCallableOptions(
          timeout: const Duration(seconds: 10),
        ),
      );
      try {
        InvoiceModel model = currentInvoiceModel.value;
        double totalLessDeposit = model.total - model.depositAmount;
        final result = await callable.call(CreateStripeCheckoutFunctionModel(
          amount: model.isDepositPaid ? totalLessDeposit : model.total,
          clientFullName: model.clientFullName,
          clientEmail: model.clientEmail,
          stripeAccountId: stripeConnectAccountId,
          userId: userId,
          workspaceId: workspaceId,
          invoiceId: model.id,
          estimateId: model.estimateId,
          isDeposit: false,
          currencyCode: model.currencyData.code.toLowerCase(),
        ).toMap());
        log("response... ${jsonEncode(result.data)}");
        if (result.data["statusCode"] == 200) {
          currentInvoiceModel.value.stripePaymentUrl =
              result.data["data"]["url"];
        } else {
          log("##### ${result.data["message"]}");
        }
      } catch (e) {
        log("##### ${e.toString()}");
      }
    } */
    if (isEdit) {
      currentInvoiceModel.value.updatedAt =
          Timestamp.now().millisecondsSinceEpoch;
      currentInvoiceModel.value.invoicePdfGenerationStatus =
          AppConstant.processing;
      currentInvoiceModel.value.invoicePdfUrl = "";
      await doc.update(currentInvoiceModel.value.toMap());
    } else {
      currentInvoiceModel.value.createdAt =
          Timestamp.now().millisecondsSinceEpoch;
      currentInvoiceModel.value.invoicePdfGenerationStatus =
          AppConstant.processing;
      await doc.set(currentInvoiceModel.value.toMap());
      if (isEstimateInvoice) {
        estimatesController.addInvoiceIdToEstimate(
          estimateId: currentInvoiceEstimateModel.id,
          invoiceId: doc.id,
        );
      }
      await updateWorkspaceInvNo(currentInvoiceModel.value.invoiceNumber);
    }
    if (isPaid) {
      if (isEstimateInvoice) {
        estimatesController.markEstimateAsPaid(
            estId: currentInvoiceModel.value.estimateId);
      }
    }
  }

  deleteAttachment(String path) async {
    await firebaseStorageController.storageService.deleteFile(path);
    await firebaseStorageController.deleteMetadataDoc(path: path);
  }

  uploadInvoiceDocuments({required bool isEdit}) async {
    String workspaceId =
        CacheStorageService.instance.read(AppConstant.workspaceId);
    if (isEdit) {
      int invoiceIndex = invoicesList
          .indexWhere((element) => element.id == currentInvoiceModel.value.id);
      if (invoiceIndex != -1) {
        for (var attachment in invoicesList[invoiceIndex].attachments) {
          bool exists = currentInvoiceModel.value.attachments
              .where((element) => element.path == attachment.path)
              .isNotEmpty;
          if (!exists) {
            deleteAttachment(attachment.path);
          }
        }
      }
    }
    for (int i = 0; i < currentInvoiceModel.value.attachments.length; i++) {
      if (currentInvoiceModel.value.attachments[i].attachmentBytes != null) {
        AttachmentModel attachmentModel =
            currentInvoiceModel.value.attachments[i];
        Uint8List bytes = attachmentModel.attachmentBytes!;
        DateTime time = DateTime.now();
        String path =
            "$workspaceId/${AppConstant.invoices}/${currentInvoiceModel.value.id}/${AppConstant.attachmentsStorage}/${time.toString()}";
        String contentType = currentInvoiceModel.value.attachments[i].mimeType;
        StorageUploadMetadataModel returnData =
            await firebaseStorageController.storageService.putData(
          bytes: bytes,
          path: path,
          contentType: contentType,
        );
        currentInvoiceModel.value.attachments[i].url = returnData.url;
        currentInvoiceModel.value.attachments[i].path = returnData.path;
        await firebaseStorageController.deleteMetadataDoc(path: path);
        await firebaseStorageController.createMetadataDoc(
          metadata: StorageFileMetadataModel(
            path: returnData.path,
            url: returnData.url,
            contentType: contentType,
            size: bytes.length,
            formattedSize: firebaseStorageController.storageService
                .formatBytes(bytes.length),
            extension: attachmentModel.fileExtension,
            createdAt: attachmentModel.createdAt,
            referenceType: AppConstant.invoice,
            referenceId: currentInvoiceModel.value.id,
          ),
        );
        currentInvoiceModel.value.attachments[i].attachmentBytes = null;
      }
    }
  }

  setPaidInvoiceFields({required int paidAtTimestamp}) {
    currentInvoiceModel.value.invoiceStatus = AppConstant.paid;
    currentInvoiceModel.value.isPaid = true;
    currentInvoiceModel.value.paidAt = paidAtTimestamp;
    currentInvoiceModel.value.updatedAt = paidAtTimestamp;
    currentInvoiceModel.value.paidAmount = currentInvoiceModel.value.total;
  }

  markInvoiceAsPaid({
    required String invId,
    required bool isEstimateInvoice,
    required bool markEstimateAsPaid,
    required String paymentMethod,
  }) async {
    int invIndex = invoicesList.indexWhere((element) => element.id == invId);
    int paidAtTimestamp = Timestamp.now().millisecondsSinceEpoch;
    if (invIndex == -1) {
      await getInvoiceById(
        invId: invId,
        includeEstimatePrices: true,
        setAsCurrentInvoice: false,
      );
      invIndex = invoicesList.indexWhere((element) => element.id == invId);
    }
    if (invIndex != -1) {
      currentInvoiceModel.value = InvoiceModel.fromMap(
        data: invoicesList[invIndex].toMap(),
        includePrices: true,
      );
      currentInvoiceModel.value.paymentMethod = paymentMethod;
      setPaidInvoiceFields(paidAtTimestamp: paidAtTimestamp);
      if (currentInvoiceModel.value.isRecurring) {
        handlePaidRecurringInvoice(paidAtTimestamp: paidAtTimestamp);
      }
      String workspaceId =
          CacheStorageService.instance.read(AppConstant.workspaceId);
      currentInvoiceModel.value.invoicePdfGenerationStatus =
          AppConstant.processing;
      currentInvoiceModel.value.invoicePdfUrl = "";
      await fireStore
          .collection(AppConstant.workspacesCollection)
          .doc(workspaceId)
          .collection(AppConstant.invoicesCollection)
          .doc(currentInvoiceModel.value.id)
          .update(currentInvoiceModel.value.toMap());
      if (isEstimateInvoice && markEstimateAsPaid) {
        estimatesController.markEstimateAsPaid(
            estId: currentInvoiceModel.value.estimateId);
      }
      /* analyticsController.increaseInvoiceTotal(
        services: currentInvoiceModel.value.servicesList,
        discountPercentage: currentInvoiceModel.value.discountPercentage,
        taxPercentage: currentInvoiceModel.value.taxPercentage,
        isQuickInvoice: !isEstimateInvoice,
        invoiceTotal: currentInvoiceModel.value.total,
      ); */
    }
  }

  getAllServices() async {
    allInvoiceServicesList.clear();
    if (servicesController.servicesList.isEmpty) {
      await servicesController.getServices();
    }
    for (var service in servicesController.servicesList) {
      SellingServiceModel invoiceServiceModel = SellingServiceModel(
        serviceImageUrl: service.imageUrl,
        serviceIndustry: service.industry,
        serviceDescription: service.serviceDescription,
        serviceId: service.id,
        serviceName: service.serviceName,
        servicePriceType: service.priceType,
        serviceUnits: 0,
        serviceUnitPrice: service.unitPrice,
        serviceFlatRate: 0,
        serviceTotal: 0,
        serviceNumber: service.serviceNumber,
      );
      allInvoiceServicesList.add(invoiceServiceModel);
    }
  }

  updateInvoiceItems({
    required String itemName,
    required String itemDescription,
    required double units,
    required double unitPrice,
    required bool isEdit,
    required int itemIndex,
  }) {
    bool exists = allInvoiceServicesList
        .where((element) => element.serviceName == itemName)
        .isNotEmpty;
    if (!exists && isEdit) {
      currentInvoiceModel.value.servicesList[itemIndex].serviceDescription =
          itemDescription;
      currentInvoiceModel.value.servicesList[itemIndex].serviceUnits = units;
      currentInvoiceModel.value.servicesList[itemIndex].serviceUnitPrice =
          unitPrice;
      currentInvoiceModel.value.servicesList[itemIndex].serviceTotal =
          units * unitPrice;
    }
    for (var element in allInvoiceServicesList) {
      if (element.serviceName == itemName) {
        SellingServiceModel invoiceServiceModel = SellingServiceModel(
          serviceImageUrl: element.serviceImageUrl,
          serviceIndustry: element.serviceIndustry,
          serviceDescription: itemDescription.isNotEmpty
              ? itemDescription
              : element.serviceDescription,
          serviceId: element.serviceId,
          serviceName: element.serviceName,
          servicePriceType: element.servicePriceType,
          serviceUnits: units,
          serviceUnitPrice: unitPrice,
          serviceFlatRate: 0,
          serviceTotal: units * unitPrice,
          serviceNumber: element.serviceNumber,
        );
        if (isEdit) {
          currentInvoiceModel.value.servicesList[itemIndex] =
              invoiceServiceModel;
        } else {
          currentInvoiceModel.value.servicesList.add(invoiceServiceModel);
        }
      }
    }
    updateInvoiceTotals();
  }

  deleteItemFromInvoice({
    required int index,
  }) {
    currentInvoiceModel.value.servicesList.removeAt(index);
    currentInvoiceModel.refresh();
    updateInvoiceTotals();
  }

  updateInvoiceTotals() {
    currentInvoiceModel.value.subTotal = 0;
    for (var element in currentInvoiceModel.value.servicesList) {
      currentInvoiceModel.value.subTotal += element.serviceTotal;
    }
    currentInvoiceModel.value.subTotal =
        currentInvoiceModel.value.subTotal.toPrecision(2);
    if (currentInvoiceModel.value.subTotal > 0) {
      if (currentInvoiceModel.value.discountPercentageEnabled) {
        currentInvoiceModel.value.discountAmount =
            ((currentInvoiceModel.value.subTotal *
                        currentInvoiceModel.value.discountPercentage) /
                    100)
                .toPrecision(2);
      } else {
        currentInvoiceModel.value.discountPercentage =
            ((currentInvoiceModel.value.discountAmount * 100) /
                    currentInvoiceModel.value.subTotal)
                .toPrecision(2);
      }
    } else {
      currentInvoiceModel.value.discountAmount = 0;
      currentInvoiceModel.value.discountPercentage = 0;
    }
    currentInvoiceModel.value.taxAmount = ((currentInvoiceModel.value.subTotal *
                currentInvoiceModel.value.taxPercentage) /
            100)
        .toPrecision(2);
    currentInvoiceModel.value.total = (currentInvoiceModel.value.subTotal +
            currentInvoiceModel.value.taxAmount -
            currentInvoiceModel.value.discountAmount)
        .toPrecision(2);
    if (currentInvoiceModel.value.total > 0) {
      if (currentInvoiceModel.value.depositPercentageEnabled &&
          !currentInvoiceModel.value.isDepositPaid) {
        currentInvoiceModel.value.depositAmount =
            ((currentInvoiceModel.value.total *
                        currentInvoiceModel.value.depositPercentage) /
                    100)
                .toPrecision(2);
      } else {
        currentInvoiceModel.value.depositPercentage =
            ((currentInvoiceModel.value.depositAmount * 100) /
                    currentInvoiceModel.value.total)
                .toPrecision(2);
      }
    }
    currentInvoiceModel.refresh();
  }

  setInvoiceTotalsFromEstimate({required EstimateModel estimateModel}) {
    currentInvoiceModel.value.subTotal = estimateModel.subTotal;
    currentInvoiceModel.value.discountAmount = estimateModel.discountAmount;
    currentInvoiceModel.value.discountPercentage =
        estimateModel.discountPercentage;
    currentInvoiceModel.value.discountPercentageEnabled =
        estimateModel.discountPercentageEnabled;
    currentInvoiceModel.value.depositPercentageEnabled =
        estimateModel.depositPercentageEnabled;
    currentInvoiceModel.value.taxAmount = estimateModel.taxAmount;
    currentInvoiceModel.value.taxPercentage = estimateModel.taxPercentage;
    currentInvoiceModel.value.total = estimateModel.total;
    currentInvoiceModel.value.depositAmount = estimateModel.depositAmount;
    currentInvoiceModel.value.depositPercentage =
        estimateModel.depositPercentage;
    currentInvoiceModel.value.isDepositPaid = estimateModel.isDepositPaid;
    currentInvoiceModel.value.depositPaidAt = estimateModel.depositPaidAt;
    currentInvoiceModel.refresh();
  }

  updateDiscountPercentageEnabled(bool value) {
    currentInvoiceModel.value.discountPercentageEnabled = value;
    if (currentInvoiceModel.value.subTotal == 0) return;
    // if value is true then calculate discount percentage from discount amount
    if (value) {
      currentInvoiceModel.value.discountPercentage =
          ((currentInvoiceModel.value.discountAmount * 100) /
                  currentInvoiceModel.value.subTotal)
              .toPrecision(2);
    } else {
      currentInvoiceModel.value.discountAmount =
          ((currentInvoiceModel.value.subTotal *
                      currentInvoiceModel.value.discountPercentage) /
                  100)
              .toPrecision(2);
    }
    currentInvoiceModel.refresh();
  }

  updateDepositPercentageEnabled(bool value) {
    currentInvoiceModel.value.depositPercentageEnabled = value;
    if (currentInvoiceModel.value.total == 0) return;
    // if value is true then calculate deposit percentage from deposit amount
    if (value) {
      currentInvoiceModel.value.depositPercentage =
          ((currentInvoiceModel.value.depositAmount * 100) /
                  currentInvoiceModel.value.total)
              .toPrecision(2);
    } else {
      currentInvoiceModel.value.depositAmount =
          ((currentInvoiceModel.value.total *
                      currentInvoiceModel.value.depositPercentage) /
                  100)
              .toPrecision(2);
    }
    currentInvoiceModel.refresh();
  }

  void getInvoiceAttachment(
      {required ImageSource imageSource, bool file = false}) async {
    List<AttachmentModel> attachments =
        await firebaseStorageController.getAttachments(
      imageSource: imageSource,
      file: file,
    );
    if (attachments.isNotEmpty) {
      currentInvoiceModel.value.attachments.addAll(attachments);
      currentInvoiceModel.refresh();
      Get.back();
    }
  }

  deleteInvoiceAttachment(int index) {
    currentInvoiceModel.value.attachments.removeAt(index);
    currentInvoiceModel.refresh();
  }

  setInvoiceDataForPdfGeneration({
    required InvoiceModel invModel,
    required bool includePrices,
  }) async {
    currentInvoiceModel.value = InvoiceModel.fromMap(
      data: invModel.toMap(),
      includePrices: includePrices,
    );
  }

  setInvoiceDataForEdit({
    required InvoiceModel invModel,
    required ClientModel clientModel,
  }) {
    currentInvoiceModel.value = InvoiceModel.fromMap(
      data: invModel.toMap(),
      includePrices: true,
    );
    currentClientModel.value = clientModel;
  }

  setInvoiceDataForEditEstimate({
    required String invoiceId,
    required EstimateModel estimateModel,
  }) async {
    int invIndex =
        invoicesList.indexWhere((element) => element.id == invoiceId);
    if (invIndex == -1) {
      await getInvoiceById(
        invId: invoiceId,
        includeEstimatePrices: true,
        setAsCurrentInvoice: true,
      );
    } else {
      currentInvoiceModel.value = InvoiceModel.fromMap(
        data: invoicesList[invIndex].toMap(),
        includePrices: true,
      );
    }
    currentInvoiceEstimateModel = EstimateModel.fromMap(
      data: estimateModel.toMap(),
      includePrices: true,
    );
    currentClientModel.value = ClientModel.empty();
    int clientIndex = clientsController.clientsData.indexWhere(
        (element) => element.id == currentInvoiceModel.value.clientId);
    if (clientIndex != -1) {
      currentClientModel.value = ClientModel.fromMap(
          clientsController.clientsData[clientIndex].toMap());
    }
  }

  createInvoiceFromEstimate({
    required EstimateModel estimateModel,
    required ClientModel clientModel,
    required bool isPaid,
    required String paymentMethod,
  }) async {
    setInvoiceDataForCreateEstimate(
      estimateModel: estimateModel,
      clientModel: clientModel,
    );
    if (isPaid) {
      setPaidInvoiceFields(
        paidAtTimestamp: Timestamp.now().millisecondsSinceEpoch,
      );
      currentInvoiceModel.value.paymentMethod = paymentMethod;
    }
    await createInvoiceDoc();
    await saveInvoiceData(isEdit: false, isEstimateInvoice: true);
    if (isPaid) {
      clearData();
    }
  }

  setInvoiceDataForCreateEstimate({
    required EstimateModel estimateModel,
    required ClientModel clientModel,
  }) {
    currentInvoiceEstimateModel = EstimateModel.fromMap(
      data: estimateModel.toMap(),
      includePrices: true,
    );
    currentClientModel.value = ClientModel.fromMap(clientModel.toMap());
    setCreateInvoiceDefaultData();
    currentInvoiceModel.value.currencyData = estimateModel.currencyData;
    setClientDataFromEstimateModel(estimateModel: estimateModel);
    currentInvoiceModel.value.servicesList = List.from(
      estimateModel.servicesList.map(
        (e) => SellingServiceModel.fromMap(
          data: e.toMap(),
          includePrices: true,
        ),
      ),
    );
    currentInvoiceModel.value.isDepositPaid = estimateModel.isDepositPaid;
    currentInvoiceModel.value.depositPaidAt = estimateModel.depositPaidAt;
    setInvoiceTotalsFromEstimate(estimateModel: estimateModel);
  }

  setCreateInvoiceDefaultData() {
    DateFormat dateFormat = DateFormat("MM/dd/yyyy");
    var workspaceModel = workspaceDetailsController.workspaceModel.value;
    currentInvoiceModel.value.clear();
    String lastNumber = workspaceModel.invoiceData.number;
    String yearPrefix = getYearPrefix();
    if (lastNumber.isEmpty) {
      currentInvoiceModel.value.invoiceNumber = "$yearPrefix-1";
    } else {
      String lastYearPrefix = lastNumber.split("-").first;
      if (lastYearPrefix != yearPrefix) {
        currentInvoiceModel.value.invoiceNumber = "$yearPrefix-1";
      } else {
        int lastNum = int.parse(lastNumber.split("-").last);
        int nextNum = lastNum + 1;
        currentInvoiceModel.value.invoiceNumber = "$yearPrefix-$nextNum";
      }
    }

    currentInvoiceModel.value.invoiceDate = dateFormat.format(DateTime.now());
    currentInvoiceModel.value.invoiceDueDate =
        dateFormat.format(DateTime.now().add(const Duration(days: 10)));
    currentInvoiceModel.value.workspaceId = workspaceModel.info.id;
    currentInvoiceModel.value.workspaceAddress =
        workspaceModel.locationData.address.formattedAddress;
    currentInvoiceModel.value.workspaceName = workspaceModel.info.name;
    currentInvoiceModel.value.workspacePhone = workspaceModel.phoneModel;
    currentInvoiceModel.value.workspaceEmail = workspaceModel.info.email;
    currentInvoiceModel.value.invoiceStatus = AppConstant.pending;
    currentInvoiceModel.value.estimateId = currentInvoiceEstimateModel.id;
    currentInvoiceModel.value.estimateType =
        currentInvoiceEstimateModel.estimateType;
    currentInvoiceModel.value.currencyData = workspaceModel.currencyModel;
  }

  getDefaultInvoiceFooterData() {
    footerTitleController.value.text =
        workspaceDetailsController.workspaceModel.value.invoiceData.footerTitle;
    footerDescriptionController.value.text = workspaceDetailsController
        .workspaceModel.value.invoiceData.footerDescription;
  }

  updateInvoiceFooter(bool setAsDefaultFooter) async {
    if (setAsDefaultFooter) {
      workspaceDetailsController.updateWorkspaceInvoiceFooter(
        footerTitle: footerTitleController.value.text,
        footerDescription: footerDescriptionController.value.text,
      );
    }
    currentInvoiceModel.value.footerTitle = footerTitleController.value.text;
    currentInvoiceModel.value.footerDescription =
        footerDescriptionController.value.text;
  }

  addScheduleIdToInvoice({
    required String invoiceId,
    required String scheduleId,
  }) async {
    String workspaceId =
        CacheStorageService.instance.read(AppConstant.workspaceId);
    await fireStore
        .collection(AppConstant.workspacesCollection)
        .doc(workspaceId)
        .collection(AppConstant.invoicesCollection)
        .doc(invoiceId)
        .update({
      AppConstant.scheduleId: scheduleId,
    });
    int index = invoicesList.indexWhere((element) => element.id == invoiceId);
    if (index != -1) {
      invoicesList[index].scheduleId = scheduleId;
    }
  }

  deleteScheduleIdFromInvoice({required String invoiceId}) async {
    String workspaceId =
        CacheStorageService.instance.read(AppConstant.workspaceId);
    await fireStore
        .collection(AppConstant.workspacesCollection)
        .doc(workspaceId)
        .collection(AppConstant.invoicesCollection)
        .doc(invoiceId)
        .update({
      AppConstant.scheduleId: "",
    });
  }

  clearData() {
    currentInvoiceModel.value.clear();
    currentInvoiceEstimateModel.clear();
    currentClientModel.value = ClientModel.empty();
  }

  String formatReccurenceTypeToIntervalName(String type) {
    if (type == RecurrenceType.every_day.value) {
      return "day";
    } else if (type == RecurrenceType.every_week.value) {
      return "week";
    } else if (type == RecurrenceType.every_2_weeks.value) {
      return "biweek";
    } else if (type == RecurrenceType.every_month.value) {
      return "month";
    } else if (type == RecurrenceType.every_year.value) {
      return "year";
    } else {
      return "day";
    }
  }

  String formatIntervalNameToRecurrenceTypeValue(String type) {
    switch (type) {
      case "day":
        return RecurrenceType.every_day.value;
      case "week":
        return RecurrenceType.every_week.value;
      case "month":
        return RecurrenceType.every_month.value;
      case "year":
        return RecurrenceType.every_year.value;
      default:
        return RecurrenceType.every_day.value;
    }
  }
}
/* updateStripeRecurringInvoice({
  "user_id": "LHNc0Tc2FHM4h3DD0aKLhjsRlKG3",
  "workspace_id":"RFJPmt00etPUsQrORref",
  "main_invoice_id":"ehza4NMO9ADcVWpXQkM7",
  "recurring_invoice_id":"1piIpdmGoyhNZa1xWbax",
  "stripe_account_id":"acct_1LeWxNPM6AQf0ErS",
  "stripe_customer_id":"cus_OzLRpT2KcG27i6",
  "client_full_name":"Test Client",
  "new_amount":155,
  "old_amount":135,
  "currency_code":"gbp",
  "interval":"day",
  "interval_count":1,
  "start_date_timestamp":1700056905,
  "end_date_timestamp":1700233305,
  "stripe_schedule_subscription_id":"sub_sched_1OCjf4PM6AQf0ErS90y4LqeY",
  "stripe_active_subscription_id":"sub_1OCjf4PM6AQf0ErSmQElqMVE",
  "stripe_invoice_id":"in_1OCjzOPM6AQf0ErS35uUKRjI",
}) */

/* createStripeRecurringInvoiceSubscription({
  "user_id": "LHNc0Tc2FHM4h3DD0aKLhjsRlKG3",
  "workspace_id":"RFJPmt00etPUsQrORref",
  "invoice_id":"gcfBTr1lEiMbo7JDVhJi",
  "stripe_account_id":"acct_1LeWxNPM6AQf0ErS",
  "stripe_customer_id":"cus_OzLRpT2KcG27i6",
  "client_full_name":"Test Client",
  "amount":40,
  "currency_code":"gbp",
  "interval":"day",
  "interval_count":1,
  "start_date_timestamp":1700142395,
  "end_date_timestamp":1700318795,
}) */

/* cancelStripeRecurringInvoiceSubscription({
  "stripe_account_id":"acct_1LeWxNPM6AQf0ErS",
  "stripe_schedule_subscription_id":"sub_sched_1OD5AyPM6AQf0ErSy3gpvk0K",
}) */