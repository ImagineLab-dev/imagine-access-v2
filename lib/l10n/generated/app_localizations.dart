import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_pt.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('es'),
    Locale('pt'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Imagine Access'**
  String get appTitle;

  /// No description provided for @adminRRPP.
  ///
  /// In en, this message translates to:
  /// **'Admin / RRPP'**
  String get adminRRPP;

  /// No description provided for @doorAccess.
  ///
  /// In en, this message translates to:
  /// **'Door Access'**
  String get doorAccess;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @deviceID.
  ///
  /// In en, this message translates to:
  /// **'Device Alias'**
  String get deviceID;

  /// No description provided for @pinCode.
  ///
  /// In en, this message translates to:
  /// **'PIN Code'**
  String get pinCode;

  /// No description provided for @login.
  ///
  /// In en, this message translates to:
  /// **'LOGIN'**
  String get login;

  /// No description provided for @startAccess.
  ///
  /// In en, this message translates to:
  /// **'START ACCESS'**
  String get startAccess;

  /// No description provided for @required.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get required;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get logout;

  /// No description provided for @dashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get dashboard;

  /// Bottom-nav label for the dashboard. Must fit one short word.
  ///
  /// In en, this message translates to:
  /// **'Panel'**
  String get navPanel;

  /// Bottom-nav label for document lookup. Must fit one short word.
  ///
  /// In en, this message translates to:
  /// **'ID'**
  String get navDocument;

  /// No description provided for @totalTickets.
  ///
  /// In en, this message translates to:
  /// **'Total Tickets'**
  String get totalTickets;

  /// No description provided for @checkedIn.
  ///
  /// In en, this message translates to:
  /// **'Checked In'**
  String get checkedIn;

  /// No description provided for @scanned.
  ///
  /// In en, this message translates to:
  /// **'Scanned'**
  String get scanned;

  /// Dashboard hero card: how many issued tickets have entered
  ///
  /// In en, this message translates to:
  /// **'Attendance'**
  String get attendance;

  /// Heading of the per-category table on the dashboard
  ///
  /// In en, this message translates to:
  /// **'Breakdown by category'**
  String get breakdownByCategory;

  /// Column header of the breakdown table. Said ONCE instead of repeating "(IN/TOT)" on every row.
  ///
  /// In en, this message translates to:
  /// **'entered / issued'**
  String get enteredOfIssued;

  /// Sub-line under attendance
  ///
  /// In en, this message translates to:
  /// **'{count} not entered yet'**
  String ticketsNotEntered(int count);

  /// No description provided for @sales.
  ///
  /// In en, this message translates to:
  /// **'Sales'**
  String get sales;

  /// No description provided for @capacity.
  ///
  /// In en, this message translates to:
  /// **'Capacity'**
  String get capacity;

  /// No description provided for @createTicket.
  ///
  /// In en, this message translates to:
  /// **'Create Ticket'**
  String get createTicket;

  /// No description provided for @viewTickets.
  ///
  /// In en, this message translates to:
  /// **'View Tickets'**
  String get viewTickets;

  /// No description provided for @scanMode.
  ///
  /// In en, this message translates to:
  /// **'Scan Mode'**
  String get scanMode;

  /// No description provided for @reports.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get reports;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @general.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get general;

  /// No description provided for @defaultCurrency.
  ///
  /// In en, this message translates to:
  /// **'Default Currency'**
  String get defaultCurrency;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @accessControl.
  ///
  /// In en, this message translates to:
  /// **'Access Control'**
  String get accessControl;

  /// No description provided for @userManagement.
  ///
  /// In en, this message translates to:
  /// **'User Management'**
  String get userManagement;

  /// No description provided for @userManagementDesc.
  ///
  /// In en, this message translates to:
  /// **'Manage Admins, RRPP, and Staff roles'**
  String get userManagementDesc;

  /// No description provided for @deviceManagement.
  ///
  /// In en, this message translates to:
  /// **'Device Management'**
  String get deviceManagement;

  /// No description provided for @deviceManagementDesc.
  ///
  /// In en, this message translates to:
  /// **'Manage scanning devices and PINs'**
  String get deviceManagementDesc;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign Out'**
  String get signOut;

  /// No description provided for @signOutDesc.
  ///
  /// In en, this message translates to:
  /// **'Exit application'**
  String get signOutDesc;

  /// No description provided for @teamMembers.
  ///
  /// In en, this message translates to:
  /// **'Team Members'**
  String get teamMembers;

  /// No description provided for @noUsersFound.
  ///
  /// In en, this message translates to:
  /// **'No users found'**
  String get noUsersFound;

  /// No description provided for @admin.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get admin;

  /// No description provided for @rrpp.
  ///
  /// In en, this message translates to:
  /// **'RRPP'**
  String get rrpp;

  /// No description provided for @door.
  ///
  /// In en, this message translates to:
  /// **'Door'**
  String get door;

  /// No description provided for @devices.
  ///
  /// In en, this message translates to:
  /// **'Devices'**
  String get devices;

  /// No description provided for @noDevicesRegistered.
  ///
  /// In en, this message translates to:
  /// **'No devices registered'**
  String get noDevicesRegistered;

  /// No description provided for @addNewDevice.
  ///
  /// In en, this message translates to:
  /// **'Add New Device'**
  String get addNewDevice;

  /// No description provided for @alias.
  ///
  /// In en, this message translates to:
  /// **'Alias (e.g. Gate 1)'**
  String get alias;

  /// No description provided for @deviceIdLabel.
  ///
  /// In en, this message translates to:
  /// **'Device ID'**
  String get deviceIdLabel;

  /// No description provided for @pinLabel.
  ///
  /// In en, this message translates to:
  /// **'PIN'**
  String get pinLabel;

  /// No description provided for @savePinWarning.
  ///
  /// In en, this message translates to:
  /// **'⚠️ Save this PIN now. It cannot be viewed again'**
  String get savePinWarning;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @disabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get disabled;

  /// No description provided for @manageEvents.
  ///
  /// In en, this message translates to:
  /// **'Manage Events'**
  String get manageEvents;

  /// No description provided for @events.
  ///
  /// In en, this message translates to:
  /// **'Events'**
  String get events;

  /// No description provided for @active.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get active;

  /// No description provided for @archived.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get archived;

  /// No description provided for @noEventsFound.
  ///
  /// In en, this message translates to:
  /// **'No events found'**
  String get noEventsFound;

  /// No description provided for @createEvent.
  ///
  /// In en, this message translates to:
  /// **'Create Event'**
  String get createEvent;

  /// No description provided for @editEvent.
  ///
  /// In en, this message translates to:
  /// **'Edit Event'**
  String get editEvent;

  /// No description provided for @eventDetails.
  ///
  /// In en, this message translates to:
  /// **'Event Details'**
  String get eventDetails;

  /// No description provided for @eventName.
  ///
  /// In en, this message translates to:
  /// **'Event Name'**
  String get eventName;

  /// No description provided for @slug.
  ///
  /// In en, this message translates to:
  /// **'Slug (URL ID)'**
  String get slug;

  /// No description provided for @date.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get date;

  /// No description provided for @time.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get time;

  /// No description provided for @venueName.
  ///
  /// In en, this message translates to:
  /// **'Venue Name'**
  String get venueName;

  /// No description provided for @address.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get address;

  /// No description provided for @city.
  ///
  /// In en, this message translates to:
  /// **'City'**
  String get city;

  /// No description provided for @currency.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get currency;

  /// No description provided for @ticketTypes.
  ///
  /// In en, this message translates to:
  /// **'Ticket Types'**
  String get ticketTypes;

  /// No description provided for @addTicketType.
  ///
  /// In en, this message translates to:
  /// **'Add Ticket Type'**
  String get addTicketType;

  /// No description provided for @saveEvent.
  ///
  /// In en, this message translates to:
  /// **'SAVE EVENT'**
  String get saveEvent;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @price.
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get price;

  /// No description provided for @tickets.
  ///
  /// In en, this message translates to:
  /// **'Tickets'**
  String get tickets;

  /// No description provided for @newTicket.
  ///
  /// In en, this message translates to:
  /// **'New Ticket'**
  String get newTicket;

  /// No description provided for @buyerInfo.
  ///
  /// In en, this message translates to:
  /// **'Buyer Info'**
  String get buyerInfo;

  /// No description provided for @fullName.
  ///
  /// In en, this message translates to:
  /// **'Full Name'**
  String get fullName;

  /// No description provided for @idNumber.
  ///
  /// In en, this message translates to:
  /// **'ID Number'**
  String get idNumber;

  /// No description provided for @phoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Phone Number'**
  String get phoneNumber;

  /// No description provided for @ticketDetails.
  ///
  /// In en, this message translates to:
  /// **'Ticket Details'**
  String get ticketDetails;

  /// No description provided for @event.
  ///
  /// In en, this message translates to:
  /// **'Event'**
  String get event;

  /// No description provided for @ticketType.
  ///
  /// In en, this message translates to:
  /// **'Ticket Type'**
  String get ticketType;

  /// No description provided for @quantity.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get quantity;

  /// No description provided for @totalAmount.
  ///
  /// In en, this message translates to:
  /// **'Total Amount'**
  String get totalAmount;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'NEXT'**
  String get next;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'BACK'**
  String get back;

  /// No description provided for @confirmPurchase.
  ///
  /// In en, this message translates to:
  /// **'CONFIRM PURCHASE'**
  String get confirmPurchase;

  /// No description provided for @searchTickets.
  ///
  /// In en, this message translates to:
  /// **'Search tickets...'**
  String get searchTickets;

  /// No description provided for @filterByEvent.
  ///
  /// In en, this message translates to:
  /// **'Filter by Event'**
  String get filterByEvent;

  /// No description provided for @allEvents.
  ///
  /// In en, this message translates to:
  /// **'All Events'**
  String get allEvents;

  /// No description provided for @valid.
  ///
  /// In en, this message translates to:
  /// **'Valid'**
  String get valid;

  /// No description provided for @used.
  ///
  /// In en, this message translates to:
  /// **'Used'**
  String get used;

  /// No description provided for @voided.
  ///
  /// In en, this message translates to:
  /// **'Void'**
  String get voided;

  /// No description provided for @scanner.
  ///
  /// In en, this message translates to:
  /// **'Scanner'**
  String get scanner;

  /// No description provided for @scanQRCode.
  ///
  /// In en, this message translates to:
  /// **'Scan QR Code'**
  String get scanQRCode;

  /// No description provided for @accessGranted.
  ///
  /// In en, this message translates to:
  /// **'ACCESS GRANTED'**
  String get accessGranted;

  /// No description provided for @accessDenied.
  ///
  /// In en, this message translates to:
  /// **'ACCESS DENIED'**
  String get accessDenied;

  /// No description provided for @alreadyUsed.
  ///
  /// In en, this message translates to:
  /// **'ALREADY USED'**
  String get alreadyUsed;

  /// No description provided for @invalidTicket.
  ///
  /// In en, this message translates to:
  /// **'INVALID TICKET'**
  String get invalidTicket;

  /// No description provided for @tapToScan.
  ///
  /// In en, this message translates to:
  /// **'Tap to Scan'**
  String get tapToScan;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @enableStaffTickets.
  ///
  /// In en, this message translates to:
  /// **'Enable Staff/Crew Tickets'**
  String get enableStaffTickets;

  /// No description provided for @enableGuestTickets.
  ///
  /// In en, this message translates to:
  /// **'Enable Guest List/Invitations'**
  String get enableGuestTickets;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @yes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get yes;

  /// No description provided for @no.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get no;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loading;

  /// No description provided for @error.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get error;

  /// No description provided for @success.
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get success;

  /// No description provided for @quickActions.
  ///
  /// In en, this message translates to:
  /// **'Quick Actions'**
  String get quickActions;

  /// No description provided for @recentActivity.
  ///
  /// In en, this message translates to:
  /// **'Recent Activity'**
  String get recentActivity;

  /// No description provided for @viewAll.
  ///
  /// In en, this message translates to:
  /// **'View All'**
  String get viewAll;

  /// No description provided for @standardGuests.
  ///
  /// In en, this message translates to:
  /// **'Standard Guests'**
  String get standardGuests;

  /// No description provided for @statistics.
  ///
  /// In en, this message translates to:
  /// **'Statistics'**
  String get statistics;

  /// No description provided for @enteringPerHour.
  ///
  /// In en, this message translates to:
  /// **'Entering Per Hour'**
  String get enteringPerHour;

  /// No description provided for @rrppPerformance.
  ///
  /// In en, this message translates to:
  /// **'RRPP Performance'**
  String get rrppPerformance;

  /// No description provided for @salesTrend.
  ///
  /// In en, this message translates to:
  /// **'Sales Trend'**
  String get salesTrend;

  /// No description provided for @pleaseSelectEvent.
  ///
  /// In en, this message translates to:
  /// **'Please select an event first!'**
  String get pleaseSelectEvent;

  /// No description provided for @selectEvent.
  ///
  /// In en, this message translates to:
  /// **'Select Event'**
  String get selectEvent;

  /// No description provided for @couldNotLoadActivity.
  ///
  /// In en, this message translates to:
  /// **'Could not load activity'**
  String get couldNotLoadActivity;

  /// No description provided for @noRecentScans.
  ///
  /// In en, this message translates to:
  /// **'No recent scans'**
  String get noRecentScans;

  /// No description provided for @viewAllTickets.
  ///
  /// In en, this message translates to:
  /// **'VIEW ALL TICKETS'**
  String get viewAllTickets;

  /// No description provided for @ticketCreated.
  ///
  /// In en, this message translates to:
  /// **'Ticket Created!'**
  String get ticketCreated;

  /// No description provided for @pdfGeneratedDesc.
  ///
  /// In en, this message translates to:
  /// **'PDF generated and email sent successfully.'**
  String get pdfGeneratedDesc;

  /// No description provided for @createAnother.
  ///
  /// In en, this message translates to:
  /// **'Create Another'**
  String get createAnother;

  /// No description provided for @selectTicketType.
  ///
  /// In en, this message translates to:
  /// **'Select Ticket Type'**
  String get selectTicketType;

  /// No description provided for @noTicketTypesAvailable.
  ///
  /// In en, this message translates to:
  /// **'No ticket types available for this event.'**
  String get noTicketTypesAvailable;

  /// No description provided for @reviewDetails.
  ///
  /// In en, this message translates to:
  /// **'Review Details'**
  String get reviewDetails;

  /// No description provided for @guest.
  ///
  /// In en, this message translates to:
  /// **'Guest'**
  String get guest;

  /// No description provided for @createAndSend.
  ///
  /// In en, this message translates to:
  /// **'CREATE & SEND'**
  String get createAndSend;

  /// No description provided for @pleaseSelectTicketType.
  ///
  /// In en, this message translates to:
  /// **'Please select a ticket type'**
  String get pleaseSelectTicketType;

  /// No description provided for @deleteEventQuery.
  ///
  /// In en, this message translates to:
  /// **'Delete Event?'**
  String get deleteEventQuery;

  /// No description provided for @deleteEventConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete event? This cannot be undone if tickets exist.'**
  String get deleteEventConfirm;

  /// No description provided for @deleteErrorMessage.
  ///
  /// In en, this message translates to:
  /// **'Cannot delete: Tickets likely exist. Archive instead.'**
  String get deleteErrorMessage;

  /// No description provided for @whatToDo.
  ///
  /// In en, this message translates to:
  /// **'What would you like to do?'**
  String get whatToDo;

  /// No description provided for @selectForScanning.
  ///
  /// In en, this message translates to:
  /// **'SELECT FOR SCANNING'**
  String get selectForScanning;

  /// No description provided for @selected.
  ///
  /// In en, this message translates to:
  /// **'Selected'**
  String get selected;

  /// No description provided for @types.
  ///
  /// In en, this message translates to:
  /// **'Types'**
  String get types;

  /// No description provided for @guestList.
  ///
  /// In en, this message translates to:
  /// **'GUEST LIST'**
  String get guestList;

  /// No description provided for @noTicketsFound.
  ///
  /// In en, this message translates to:
  /// **'No tickets found'**
  String get noTicketsFound;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search guest or email...'**
  String get searchHint;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'ALL'**
  String get all;

  /// No description provided for @validCaps.
  ///
  /// In en, this message translates to:
  /// **'VALID'**
  String get validCaps;

  /// No description provided for @usedCaps.
  ///
  /// In en, this message translates to:
  /// **'USED'**
  String get usedCaps;

  /// No description provided for @voidCaps.
  ///
  /// In en, this message translates to:
  /// **'VOID'**
  String get voidCaps;

  /// No description provided for @readyToScan.
  ///
  /// In en, this message translates to:
  /// **'Ready to Scan'**
  String get readyToScan;

  /// Instruction shown under the scanner viewfinder
  ///
  /// In en, this message translates to:
  /// **'Align the QR code inside the frame'**
  String get alignQrInFrame;

  /// No description provided for @firstEntry.
  ///
  /// In en, this message translates to:
  /// **'FIRST ENTRY:'**
  String get firstEntry;

  /// No description provided for @tapToDismiss.
  ///
  /// In en, this message translates to:
  /// **'TAP TO DISMISS'**
  String get tapToDismiss;

  /// No description provided for @newEvent.
  ///
  /// In en, this message translates to:
  /// **'New Event'**
  String get newEvent;

  /// No description provided for @location.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get location;

  /// No description provided for @currencyLabel.
  ///
  /// In en, this message translates to:
  /// **'CURRENCY'**
  String get currencyLabel;

  /// No description provided for @addType.
  ///
  /// In en, this message translates to:
  /// **'Add Type'**
  String get addType;

  /// No description provided for @noTicketTypesAdded.
  ///
  /// In en, this message translates to:
  /// **'No ticket types added yet.'**
  String get noTicketTypesAdded;

  /// No description provided for @forceRefresh.
  ///
  /// In en, this message translates to:
  /// **'Force App Refresh'**
  String get forceRefresh;

  /// No description provided for @refreshing.
  ///
  /// In en, this message translates to:
  /// **'Refreshing data...'**
  String get refreshing;

  /// No description provided for @resendEmail.
  ///
  /// In en, this message translates to:
  /// **'Resend Email'**
  String get resendEmail;

  /// No description provided for @voidTicket.
  ///
  /// In en, this message translates to:
  /// **'Void Ticket'**
  String get voidTicket;

  /// No description provided for @confirmVoid.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to void this ticket?'**
  String get confirmVoid;

  /// No description provided for @ticketVoided.
  ///
  /// In en, this message translates to:
  /// **'Ticket voided successfully'**
  String get ticketVoided;

  /// No description provided for @emailResent.
  ///
  /// In en, this message translates to:
  /// **'Email resent successfully'**
  String get emailResent;

  /// No description provided for @sending.
  ///
  /// In en, this message translates to:
  /// **'Sending...'**
  String get sending;

  /// No description provided for @voiding.
  ///
  /// In en, this message translates to:
  /// **'Voiding...'**
  String get voiding;

  /// No description provided for @emailSent.
  ///
  /// In en, this message translates to:
  /// **'Email Sent'**
  String get emailSent;

  /// No description provided for @details.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get details;

  /// No description provided for @themeMode.
  ///
  /// In en, this message translates to:
  /// **'Theme Mode'**
  String get themeMode;

  /// No description provided for @select.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get select;

  /// No description provided for @register.
  ///
  /// In en, this message translates to:
  /// **'REGISTER'**
  String get register;

  /// No description provided for @signUp.
  ///
  /// In en, this message translates to:
  /// **'Create Account'**
  String get signUp;

  /// No description provided for @displayName.
  ///
  /// In en, this message translates to:
  /// **'Display Name'**
  String get displayName;

  /// No description provided for @doNotHaveAccount.
  ///
  /// In en, this message translates to:
  /// **'Don\'t have an account?'**
  String get doNotHaveAccount;

  /// No description provided for @alreadyHaveAccount.
  ///
  /// In en, this message translates to:
  /// **'Already have an account?'**
  String get alreadyHaveAccount;

  /// No description provided for @manageTeam.
  ///
  /// In en, this message translates to:
  /// **'Manage Team'**
  String get manageTeam;

  /// No description provided for @mySales.
  ///
  /// In en, this message translates to:
  /// **'MY SALES'**
  String get mySales;

  /// No description provided for @validated.
  ///
  /// In en, this message translates to:
  /// **'VALIDATED'**
  String get validated;

  /// No description provided for @guestsIn.
  ///
  /// In en, this message translates to:
  /// **'GUESTS IN'**
  String get guestsIn;

  /// No description provided for @myQuotas.
  ///
  /// In en, this message translates to:
  /// **'MY QUOTAS'**
  String get myQuotas;

  /// No description provided for @commission.
  ///
  /// In en, this message translates to:
  /// **'COMMISSION'**
  String get commission;

  /// No description provided for @pending.
  ///
  /// In en, this message translates to:
  /// **'PENDING'**
  String get pending;

  /// No description provided for @toEnter.
  ///
  /// In en, this message translates to:
  /// **'TO ENTER'**
  String get toEnter;

  /// No description provided for @guestEntry.
  ///
  /// In en, this message translates to:
  /// **'GUEST ENTRY'**
  String get guestEntry;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'REFRESH'**
  String get refresh;

  /// No description provided for @staff.
  ///
  /// In en, this message translates to:
  /// **'STAFF'**
  String get staff;

  /// No description provided for @guests.
  ///
  /// In en, this message translates to:
  /// **'GUESTS'**
  String get guests;

  /// No description provided for @normal.
  ///
  /// In en, this message translates to:
  /// **'STANDARD'**
  String get normal;

  /// No description provided for @view.
  ///
  /// In en, this message translates to:
  /// **'VIEW'**
  String get view;

  /// No description provided for @newTicketInvitation.
  ///
  /// In en, this message translates to:
  /// **'NEW TICKET / INVITATION'**
  String get newTicketInvitation;

  /// No description provided for @searchTicketBtn.
  ///
  /// In en, this message translates to:
  /// **'SEARCH TICKET'**
  String get searchTicketBtn;

  /// No description provided for @salesTitle.
  ///
  /// In en, this message translates to:
  /// **'SALES'**
  String get salesTitle;

  /// No description provided for @totalIssued.
  ///
  /// In en, this message translates to:
  /// **'TOTAL ISSUED'**
  String get totalIssued;

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'TODAY'**
  String get today;

  /// No description provided for @remaining.
  ///
  /// In en, this message translates to:
  /// **'REMAINING'**
  String get remaining;

  /// No description provided for @invitationsStandard.
  ///
  /// In en, this message translates to:
  /// **'STANDARD INVITATIONS'**
  String get invitationsStandard;

  /// No description provided for @invitationsGuest.
  ///
  /// In en, this message translates to:
  /// **'GUEST INVITATIONS'**
  String get invitationsGuest;

  /// No description provided for @entered.
  ///
  /// In en, this message translates to:
  /// **'ENTERED'**
  String get entered;

  /// No description provided for @toEnterTitle.
  ///
  /// In en, this message translates to:
  /// **'TO ENTER'**
  String get toEnterTitle;

  /// No description provided for @paidShort.
  ///
  /// In en, this message translates to:
  /// **'P'**
  String get paidShort;

  /// No description provided for @inviteShort.
  ///
  /// In en, this message translates to:
  /// **'I'**
  String get inviteShort;

  /// No description provided for @welcomeTagline.
  ///
  /// In en, this message translates to:
  /// **'Control access, tickets, and validation with elegance and precision'**
  String get welcomeTagline;

  /// No description provided for @welcomeMainFeatures.
  ///
  /// In en, this message translates to:
  /// **'MAIN FEATURES'**
  String get welcomeMainFeatures;

  /// No description provided for @systemOnline.
  ///
  /// In en, this message translates to:
  /// **'System online'**
  String get systemOnline;

  /// No description provided for @lockoutWaitSeconds.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Wait {seconds}s.'**
  String lockoutWaitSeconds(int seconds);

  /// No description provided for @invalidCredentials.
  ///
  /// In en, this message translates to:
  /// **'Invalid credentials.'**
  String get invalidCredentials;

  /// No description provided for @emailAlreadyRegistered.
  ///
  /// In en, this message translates to:
  /// **'This email is already registered. Try logging in.'**
  String get emailAlreadyRegistered;

  /// No description provided for @registrationFailed.
  ///
  /// In en, this message translates to:
  /// **'Registration failed. Please try again.'**
  String get registrationFailed;

  /// No description provided for @tooManyAttempts.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Please wait a moment.'**
  String get tooManyAttempts;

  /// No description provided for @companyName.
  ///
  /// In en, this message translates to:
  /// **'Company Name'**
  String get companyName;

  /// No description provided for @enterCompanyName.
  ///
  /// In en, this message translates to:
  /// **'Enter your company name'**
  String get enterCompanyName;

  /// No description provided for @invalidEmail.
  ///
  /// In en, this message translates to:
  /// **'Invalid email'**
  String get invalidEmail;

  /// No description provided for @passwordMinLength.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 8 characters'**
  String get passwordMinLength;

  /// No description provided for @confirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm Password'**
  String get confirmPassword;

  /// No description provided for @passwordsDoNotMatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get passwordsDoNotMatch;

  /// No description provided for @passwordRuleMinLength.
  ///
  /// In en, this message translates to:
  /// **'At least 8 characters'**
  String get passwordRuleMinLength;

  /// No description provided for @passwordRuleUppercase.
  ///
  /// In en, this message translates to:
  /// **'At least one uppercase letter'**
  String get passwordRuleUppercase;

  /// No description provided for @passwordRuleLowercase.
  ///
  /// In en, this message translates to:
  /// **'At least one lowercase letter'**
  String get passwordRuleLowercase;

  /// No description provided for @passwordRuleNumber.
  ///
  /// In en, this message translates to:
  /// **'At least one number'**
  String get passwordRuleNumber;

  /// No description provided for @passwordRuleSpecial.
  ///
  /// In en, this message translates to:
  /// **'At least one special character (!@#\$%^&*)'**
  String get passwordRuleSpecial;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'RETRY'**
  String get retry;

  /// No description provided for @darkMode.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get darkMode;

  /// No description provided for @lightMode.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get lightMode;

  /// No description provided for @reloadLocaleData.
  ///
  /// In en, this message translates to:
  /// **'Reloads data and checks for a new version of the app'**
  String get reloadLocaleData;

  /// No description provided for @updated.
  ///
  /// In en, this message translates to:
  /// **'Updated!'**
  String get updated;

  /// No description provided for @addMember.
  ///
  /// In en, this message translates to:
  /// **'Add Member'**
  String get addMember;

  /// No description provided for @unknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get unknown;

  /// No description provided for @deleteMemberQuestion.
  ///
  /// In en, this message translates to:
  /// **'Delete Member?'**
  String get deleteMemberQuestion;

  /// No description provided for @confirmRemoveMember.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to remove {name}?'**
  String confirmRemoveMember(String name);

  /// No description provided for @addTeamMember.
  ///
  /// In en, this message translates to:
  /// **'Add Team Member'**
  String get addTeamMember;

  /// No description provided for @roleLabel.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get roleLabel;

  /// No description provided for @userCreatedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'User created successfully!'**
  String get userCreatedSuccessfully;

  /// No description provided for @createUser.
  ///
  /// In en, this message translates to:
  /// **'Create User'**
  String get createUser;

  /// No description provided for @thisDevice.
  ///
  /// In en, this message translates to:
  /// **'THIS DEVICE'**
  String get thisDevice;

  /// No description provided for @deviceEnabled.
  ///
  /// In en, this message translates to:
  /// **'Device enabled'**
  String get deviceEnabled;

  /// No description provided for @deviceDisabled.
  ///
  /// In en, this message translates to:
  /// **'Device disabled'**
  String get deviceDisabled;

  /// No description provided for @deleteDeviceQuestion.
  ///
  /// In en, this message translates to:
  /// **'Delete Device?'**
  String get deleteDeviceQuestion;

  /// No description provided for @confirmDeleteAlias.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete \"{alias}\"?'**
  String confirmDeleteAlias(String alias);

  /// No description provided for @deviceDeleted.
  ///
  /// In en, this message translates to:
  /// **'Device deleted'**
  String get deviceDeleted;

  /// No description provided for @errorDeletingDevice.
  ///
  /// In en, this message translates to:
  /// **'Error deleting: {error}'**
  String errorDeletingDevice(String error);

  /// No description provided for @pinCopied.
  ///
  /// In en, this message translates to:
  /// **'PIN copied!'**
  String get pinCopied;

  /// No description provided for @deviceCreatedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Device created successfully!'**
  String get deviceCreatedSuccessfully;

  /// No description provided for @failedToCreateDevice.
  ///
  /// In en, this message translates to:
  /// **'Failed to create device: {error}'**
  String failedToCreateDevice(String error);

  /// No description provided for @teamForEvent.
  ///
  /// In en, this message translates to:
  /// **'Team: {eventName}'**
  String teamForEvent(String eventName);

  /// No description provided for @addStaffToEvent.
  ///
  /// In en, this message translates to:
  /// **'Add Staff to Event'**
  String get addStaffToEvent;

  /// No description provided for @noStaffAssignedToEvent.
  ///
  /// In en, this message translates to:
  /// **'No staff assigned to this event.'**
  String get noStaffAssignedToEvent;

  /// No description provided for @unknownUser.
  ///
  /// In en, this message translates to:
  /// **'Unknown User'**
  String get unknownUser;

  /// No description provided for @user.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get user;

  /// No description provided for @standardShort.
  ///
  /// In en, this message translates to:
  /// **'STANDARD'**
  String get standardShort;

  /// No description provided for @invitationShort.
  ///
  /// In en, this message translates to:
  /// **'INVIT'**
  String get invitationShort;

  /// No description provided for @vipShort.
  ///
  /// In en, this message translates to:
  /// **'VIP'**
  String get vipShort;

  /// No description provided for @selectUser.
  ///
  /// In en, this message translates to:
  /// **'Select User'**
  String get selectUser;

  /// No description provided for @roleInEvent.
  ///
  /// In en, this message translates to:
  /// **'Role in Event'**
  String get roleInEvent;

  /// No description provided for @addAction.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get addAction;

  /// No description provided for @editQuotasFor.
  ///
  /// In en, this message translates to:
  /// **'Edit Quotas: {userName}'**
  String editQuotasFor(String userName);

  /// No description provided for @standardTicketQuota.
  ///
  /// In en, this message translates to:
  /// **'Standard Ticket Quota'**
  String get standardTicketQuota;

  /// No description provided for @guestListQuotaVip.
  ///
  /// In en, this message translates to:
  /// **'Guest List Quota (VIP)'**
  String get guestListQuotaVip;

  /// No description provided for @invitationQuotaNormal.
  ///
  /// In en, this message translates to:
  /// **'Invitation Quota (Normal)'**
  String get invitationQuotaNormal;

  /// No description provided for @manualUpper.
  ///
  /// In en, this message translates to:
  /// **'MANUAL'**
  String get manualUpper;

  /// No description provided for @systemUser.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get systemUser;

  /// No description provided for @activityByLine.
  ///
  /// In en, this message translates to:
  /// **'{buyer} • by {validator}'**
  String activityByLine(String buyer, String validator);

  /// Sub-line of a scan row: how it was scanned and by whom
  ///
  /// In en, this message translates to:
  /// **'{method} • by {validator}'**
  String activityMethodLine(String method, String validator);

  /// No description provided for @sentByLine.
  ///
  /// In en, this message translates to:
  /// **'Sent by: {sender}'**
  String sentByLine(String sender);

  /// No description provided for @statusLabel.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get statusLabel;

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// No description provided for @sharedTicketMessage.
  ///
  /// In en, this message translates to:
  /// **'Shared ticket\n{link}\n\nID: {id}'**
  String sharedTicketMessage(String link, String id);

  /// No description provided for @errorWithDetail.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String errorWithDetail(String error);

  /// No description provided for @manualSearchTitle.
  ///
  /// In en, this message translates to:
  /// **'MANUAL SEARCH'**
  String get manualSearchTitle;

  /// No description provided for @manualSearchDescription.
  ///
  /// In en, this message translates to:
  /// **'Select the search type and enter data to validate entry.'**
  String get manualSearchDescription;

  /// No description provided for @searchByLabel.
  ///
  /// In en, this message translates to:
  /// **'SEARCH BY'**
  String get searchByLabel;

  /// No description provided for @searchByDocument.
  ///
  /// In en, this message translates to:
  /// **'DOCUMENT (ID)'**
  String get searchByDocument;

  /// No description provided for @searchByPhone.
  ///
  /// In en, this message translates to:
  /// **'PHONE'**
  String get searchByPhone;

  /// No description provided for @documentNumberLabel.
  ///
  /// In en, this message translates to:
  /// **'DOCUMENT NUMBER'**
  String get documentNumberLabel;

  /// No description provided for @phoneNumberLabelUpper.
  ///
  /// In en, this message translates to:
  /// **'PHONE NUMBER'**
  String get phoneNumberLabelUpper;

  /// No description provided for @searchAttendee.
  ///
  /// In en, this message translates to:
  /// **'SEARCH ATTENDEE'**
  String get searchAttendee;

  /// No description provided for @resultsFoundCount.
  ///
  /// In en, this message translates to:
  /// **'{count} RESULTS FOUND:'**
  String resultsFoundCount(int count);

  /// No description provided for @dniCiLabel.
  ///
  /// In en, this message translates to:
  /// **'ID:'**
  String get dniCiLabel;

  /// No description provided for @phoneShortLabel.
  ///
  /// In en, this message translates to:
  /// **'PHONE:'**
  String get phoneShortLabel;

  /// No description provided for @validationReason.
  ///
  /// In en, this message translates to:
  /// **'VALIDATION REASON'**
  String get validationReason;

  /// No description provided for @qrNotReadable.
  ///
  /// In en, this message translates to:
  /// **'QR not readable'**
  String get qrNotReadable;

  /// No description provided for @emailNotReceived.
  ///
  /// In en, this message translates to:
  /// **'Email not received'**
  String get emailNotReceived;

  /// No description provided for @manualValidation.
  ///
  /// In en, this message translates to:
  /// **'Manual Validation'**
  String get manualValidation;

  /// No description provided for @otherManualValidation.
  ///
  /// In en, this message translates to:
  /// **'Other / Manual Validation'**
  String get otherManualValidation;

  /// No description provided for @confirmAndValidate.
  ///
  /// In en, this message translates to:
  /// **'CONFIRM AND VALIDATE'**
  String get confirmAndValidate;

  /// No description provided for @ticketAlreadyUsedInvalid.
  ///
  /// In en, this message translates to:
  /// **'THIS TICKET WAS ALREADY USED OR IS NOT VALID'**
  String get ticketAlreadyUsedInvalid;

  /// No description provided for @manualValidationAudited.
  ///
  /// In en, this message translates to:
  /// **'AUDITED MANUAL VALIDATION'**
  String get manualValidationAudited;

  /// No description provided for @noRecordFound.
  ///
  /// In en, this message translates to:
  /// **'No record found'**
  String get noRecordFound;

  /// No description provided for @eventCreatedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Event created successfully!'**
  String get eventCreatedSuccessfully;

  /// No description provided for @ticketLoadedFromDeepLink.
  ///
  /// In en, this message translates to:
  /// **'Ticket loaded from deep link.'**
  String get ticketLoadedFromDeepLink;

  /// No description provided for @couldNotOpenSharedTicket.
  ///
  /// In en, this message translates to:
  /// **'Could not open the shared ticket.'**
  String get couldNotOpenSharedTicket;

  /// No description provided for @professionalAccessStaff.
  ///
  /// In en, this message translates to:
  /// **'Professional Access (Staff)'**
  String get professionalAccessStaff;

  /// No description provided for @createsStaffAccessTicket.
  ///
  /// In en, this message translates to:
  /// **'Creates \'Staff Access\' ticket (Price: 0)'**
  String get createsStaffAccessTicket;

  /// No description provided for @enableInvitationsNormal.
  ///
  /// In en, this message translates to:
  /// **'Enable Invitations (Normal)'**
  String get enableInvitationsNormal;

  /// No description provided for @createsInvitationTicketForQuotas.
  ///
  /// In en, this message translates to:
  /// **'Creates \'Invitation\' ticket (Price: 0) - For RRPP Quotas'**
  String get createsInvitationTicketForQuotas;

  /// No description provided for @setValidUntilTimeOptional.
  ///
  /// In en, this message translates to:
  /// **'Set Valid Until Time (Optional)'**
  String get setValidUntilTimeOptional;

  /// No description provided for @validUntilTime.
  ///
  /// In en, this message translates to:
  /// **'Valid until: {time}'**
  String validUntilTime(String time);

  /// No description provided for @toleranceMinutesLabel.
  ///
  /// In en, this message translates to:
  /// **'Entry tolerance'**
  String get toleranceMinutesLabel;

  /// No description provided for @toleranceMinutesValue.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min tolerance'**
  String toleranceMinutesValue(String minutes);

  /// No description provided for @noTolerance.
  ///
  /// In en, this message translates to:
  /// **'No tolerance'**
  String get noTolerance;

  /// No description provided for @downloadReport.
  ///
  /// In en, this message translates to:
  /// **'Download Report'**
  String get downloadReport;

  /// No description provided for @reportGenerating.
  ///
  /// In en, this message translates to:
  /// **'Generating report...'**
  String get reportGenerating;

  /// No description provided for @reportReady.
  ///
  /// In en, this message translates to:
  /// **'Report generated successfully'**
  String get reportReady;

  /// No description provided for @reportError.
  ///
  /// In en, this message translates to:
  /// **'Error generating report'**
  String get reportError;

  /// No description provided for @enableVipGuestList.
  ///
  /// In en, this message translates to:
  /// **'Enable VIP Guest List'**
  String get enableVipGuestList;

  /// No description provided for @createsVipGuestTicketForQuotas.
  ///
  /// In en, this message translates to:
  /// **'Creates \'Special Guest\' ticket (Price: 0) - For VIP Quotas'**
  String get createsVipGuestTicketForQuotas;

  /// No description provided for @ticketTypeStaffAccess.
  ///
  /// In en, this message translates to:
  /// **'Staff Access'**
  String get ticketTypeStaffAccess;

  /// No description provided for @ticketTypeInvitation.
  ///
  /// In en, this message translates to:
  /// **'Invitation'**
  String get ticketTypeInvitation;

  /// No description provided for @ticketTypeSpecialGuest.
  ///
  /// In en, this message translates to:
  /// **'Special Guest'**
  String get ticketTypeSpecialGuest;

  /// No description provided for @eventNotFound.
  ///
  /// In en, this message translates to:
  /// **'Event not found.'**
  String get eventNotFound;

  /// No description provided for @eventSelectedFromDeepLink.
  ///
  /// In en, this message translates to:
  /// **'Event selected from deep link.'**
  String get eventSelectedFromDeepLink;

  /// No description provided for @couldNotOpenSharedEvent.
  ///
  /// In en, this message translates to:
  /// **'Could not open the shared event.'**
  String get couldNotOpenSharedEvent;

  /// No description provided for @selectColor.
  ///
  /// In en, this message translates to:
  /// **'Select Color'**
  String get selectColor;

  /// No description provided for @offlineTicketQueued.
  ///
  /// In en, this message translates to:
  /// **'Offline. Ticket queued for automatic sync.'**
  String get offlineTicketQueued;

  /// No description provided for @ticketCreatedEmailFailed.
  ///
  /// In en, this message translates to:
  /// **'Ticket created, but email could not be sent.'**
  String get ticketCreatedEmailFailed;

  /// No description provided for @ticketCreatedEmailError.
  ///
  /// In en, this message translates to:
  /// **'Ticket created, email failed: {error}'**
  String ticketCreatedEmailError(String error);

  /// No description provided for @verifyEmailTitle.
  ///
  /// In en, this message translates to:
  /// **'Verify Email'**
  String get verifyEmailTitle;

  /// No description provided for @verifyEmailSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter the 6-digit code sent to {email}'**
  String verifyEmailSubtitle(String email);

  /// No description provided for @verifyEmailButton.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get verifyEmailButton;

  /// No description provided for @verifyEmailInvalidCode.
  ///
  /// In en, this message translates to:
  /// **'Enter a 6-digit code'**
  String get verifyEmailInvalidCode;

  /// No description provided for @verifyEmailResendButton.
  ///
  /// In en, this message translates to:
  /// **'Resend code'**
  String get verifyEmailResendButton;

  /// No description provided for @verifyEmailResendWait.
  ///
  /// In en, this message translates to:
  /// **'Resend in {seconds}s'**
  String verifyEmailResendWait(int seconds);

  /// No description provided for @verifyEmailResent.
  ///
  /// In en, this message translates to:
  /// **'Code resent successfully'**
  String get verifyEmailResent;

  /// No description provided for @invalidEntry.
  ///
  /// In en, this message translates to:
  /// **'INVALID ENTRY'**
  String get invalidEntry;

  /// No description provided for @entryNoLongerValid.
  ///
  /// In en, this message translates to:
  /// **'This entry is no longer valid.'**
  String get entryNoLongerValid;

  /// No description provided for @validOnlyUntil.
  ///
  /// In en, this message translates to:
  /// **'Valid only until: {date}'**
  String validOnlyUntil(String date);

  /// No description provided for @ticketMarkedVoid.
  ///
  /// In en, this message translates to:
  /// **'The ticket has been marked as VOID.'**
  String get ticketMarkedVoid;

  /// No description provided for @closeAction.
  ///
  /// In en, this message translates to:
  /// **'CLOSE'**
  String get closeAction;

  /// No description provided for @userCreatedTitle.
  ///
  /// In en, this message translates to:
  /// **'User Created'**
  String get userCreatedTitle;

  /// No description provided for @temporaryPassword.
  ///
  /// In en, this message translates to:
  /// **'Temporary password:'**
  String get temporaryPassword;

  /// No description provided for @passwordCopied.
  ///
  /// In en, this message translates to:
  /// **'Password copied'**
  String get passwordCopied;

  /// No description provided for @savePasswordWarning.
  ///
  /// In en, this message translates to:
  /// **'Save this password. The user will need it to log in.'**
  String get savePasswordWarning;

  /// No description provided for @understood.
  ///
  /// In en, this message translates to:
  /// **'Understood'**
  String get understood;

  /// No description provided for @cannotChangeOwnRole.
  ///
  /// In en, this message translates to:
  /// **'You cannot change your own role'**
  String get cannotChangeOwnRole;

  /// No description provided for @cannotDeleteSelf.
  ///
  /// In en, this message translates to:
  /// **'You cannot delete your own account'**
  String get cannotDeleteSelf;

  /// No description provided for @restoreEvent.
  ///
  /// In en, this message translates to:
  /// **'RESTORE'**
  String get restoreEvent;

  /// No description provided for @noPermission.
  ///
  /// In en, this message translates to:
  /// **'You do not have permission to access this section'**
  String get noPermission;

  /// No description provided for @specialAccess.
  ///
  /// In en, this message translates to:
  /// **'Special Access'**
  String get specialAccess;

  /// No description provided for @free.
  ///
  /// In en, this message translates to:
  /// **'FREE'**
  String get free;

  /// No description provided for @removeStaff.
  ///
  /// In en, this message translates to:
  /// **'Remove Staff'**
  String get removeStaff;

  /// No description provided for @confirmRemoveStaff.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to remove {name} from this event?'**
  String confirmRemoveStaff(String name);

  /// No description provided for @verifyEmailError.
  ///
  /// In en, this message translates to:
  /// **'The verification code is invalid or has expired.'**
  String get verifyEmailError;

  /// No description provided for @resendCodeError.
  ///
  /// In en, this message translates to:
  /// **'Could not resend the code. Please try again later.'**
  String get resendCodeError;

  /// No description provided for @eventArchived.
  ///
  /// In en, this message translates to:
  /// **'Event archived successfully.'**
  String get eventArchived;

  /// No description provided for @eventArchiveError.
  ///
  /// In en, this message translates to:
  /// **'Could not archive the event.'**
  String get eventArchiveError;

  /// No description provided for @duplicateTicketTypeNames.
  ///
  /// In en, this message translates to:
  /// **'Ticket types must have unique names. Found duplicates: {names}'**
  String duplicateTicketTypeNames(String names);

  /// No description provided for @eventSaveError.
  ///
  /// In en, this message translates to:
  /// **'Could not save the event. Please try again.'**
  String get eventSaveError;

  /// No description provided for @voidTicketError.
  ///
  /// In en, this message translates to:
  /// **'Could not void the ticket.'**
  String get voidTicketError;

  /// No description provided for @scanError.
  ///
  /// In en, this message translates to:
  /// **'Scan validation failed. Please try again.'**
  String get scanError;

  /// No description provided for @privacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyPolicy;

  /// No description provided for @termsOfService.
  ///
  /// In en, this message translates to:
  /// **'Terms of Service'**
  String get termsOfService;

  /// No description provided for @legalInfo.
  ///
  /// In en, this message translates to:
  /// **'Legal Information'**
  String get legalInfo;

  /// No description provided for @legalInfoDesc.
  ///
  /// In en, this message translates to:
  /// **'Privacy policy and terms'**
  String get legalInfoDesc;

  /// No description provided for @acceptTermsPrefix.
  ///
  /// In en, this message translates to:
  /// **'I accept the '**
  String get acceptTermsPrefix;

  /// No description provided for @acceptTermsSuffix.
  ///
  /// In en, this message translates to:
  /// **' and the '**
  String get acceptTermsSuffix;

  /// No description provided for @mustAcceptTerms.
  ///
  /// In en, this message translates to:
  /// **'You must accept the terms and privacy policy'**
  String get mustAcceptTerms;

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot your password?'**
  String get forgotPassword;

  /// No description provided for @resetPassword.
  ///
  /// In en, this message translates to:
  /// **'Reset Password'**
  String get resetPassword;

  /// No description provided for @enterEmailToReset.
  ///
  /// In en, this message translates to:
  /// **'Enter your email to receive a reset code'**
  String get enterEmailToReset;

  /// No description provided for @sendResetCode.
  ///
  /// In en, this message translates to:
  /// **'SEND CODE'**
  String get sendResetCode;

  /// No description provided for @resetCodeSent.
  ///
  /// In en, this message translates to:
  /// **'A reset code has been sent to your email'**
  String get resetCodeSent;

  /// No description provided for @enterResetCode.
  ///
  /// In en, this message translates to:
  /// **'Enter the code you received'**
  String get enterResetCode;

  /// No description provided for @newPassword.
  ///
  /// In en, this message translates to:
  /// **'New Password'**
  String get newPassword;

  /// No description provided for @confirmNewPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm New Password'**
  String get confirmNewPassword;

  /// No description provided for @changePassword.
  ///
  /// In en, this message translates to:
  /// **'CHANGE PASSWORD'**
  String get changePassword;

  /// No description provided for @passwordChanged.
  ///
  /// In en, this message translates to:
  /// **'Password changed successfully'**
  String get passwordChanged;

  /// No description provided for @resetCodeInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid or expired code'**
  String get resetCodeInvalid;

  /// No description provided for @errorNoConnection.
  ///
  /// In en, this message translates to:
  /// **'No internet connection. Check your network.'**
  String get errorNoConnection;

  /// No description provided for @errorTimeout.
  ///
  /// In en, this message translates to:
  /// **'The operation took too long. Please try again.'**
  String get errorTimeout;

  /// No description provided for @errorUnauthorized.
  ///
  /// In en, this message translates to:
  /// **'Session expired. Please sign in again.'**
  String get errorUnauthorized;

  /// No description provided for @errorForbidden.
  ///
  /// In en, this message translates to:
  /// **'You do not have permission to perform this action.'**
  String get errorForbidden;

  /// No description provided for @errorNotFound.
  ///
  /// In en, this message translates to:
  /// **'Resource not found.'**
  String get errorNotFound;

  /// No description provided for @errorBadRequest.
  ///
  /// In en, this message translates to:
  /// **'Invalid data. Check the information entered.'**
  String get errorBadRequest;

  /// No description provided for @errorCaptcha.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t verify that you\'re human. Reload the page and try again.'**
  String get errorCaptcha;

  /// No description provided for @errorServer.
  ///
  /// In en, this message translates to:
  /// **'Server error. Try again later.'**
  String get errorServer;

  /// No description provided for @errorUnknown.
  ///
  /// In en, this message translates to:
  /// **'An unexpected error occurred.'**
  String get errorUnknown;

  /// No description provided for @retryAction.
  ///
  /// In en, this message translates to:
  /// **'RETRY'**
  String get retryAction;

  /// No description provided for @errorQrValidation.
  ///
  /// In en, this message translates to:
  /// **'QR validation error'**
  String get errorQrValidation;

  /// No description provided for @errorIdValidation.
  ///
  /// In en, this message translates to:
  /// **'ID validation error'**
  String get errorIdValidation;

  /// No description provided for @offlineValidationQueued.
  ///
  /// In en, this message translates to:
  /// **'No connection. Validation queued for sync.'**
  String get offlineValidationQueued;

  /// No description provided for @urlCopied.
  ///
  /// In en, this message translates to:
  /// **'URL copied: {url}'**
  String urlCopied(String url);

  /// No description provided for @errorNoOrganization.
  ///
  /// In en, this message translates to:
  /// **'No organization found for current user. Please sign in again.'**
  String get errorNoOrganization;

  /// No description provided for @errorCreateOrgProfile.
  ///
  /// In en, this message translates to:
  /// **'Could not create organization profile. Please try again.'**
  String get errorCreateOrgProfile;

  /// No description provided for @processing.
  ///
  /// In en, this message translates to:
  /// **'PROCESSING'**
  String get processing;

  /// No description provided for @emailWithValue.
  ///
  /// In en, this message translates to:
  /// **'Email: {email}'**
  String emailWithValue(String email);

  /// No description provided for @noDataAvailable.
  ///
  /// In en, this message translates to:
  /// **'No data available yet'**
  String get noDataAvailable;

  /// No description provided for @reportFullTitle.
  ///
  /// In en, this message translates to:
  /// **'COMPLETE EVENT REPORT'**
  String get reportFullTitle;

  /// No description provided for @reportGenerated.
  ///
  /// In en, this message translates to:
  /// **'Generated: {date}'**
  String reportGenerated(String date);

  /// No description provided for @reportSummary.
  ///
  /// In en, this message translates to:
  /// **'GENERAL SUMMARY'**
  String get reportSummary;

  /// No description provided for @reportTotalTickets.
  ///
  /// In en, this message translates to:
  /// **'Total Tickets'**
  String get reportTotalTickets;

  /// No description provided for @reportValid.
  ///
  /// In en, this message translates to:
  /// **'Valid'**
  String get reportValid;

  /// No description provided for @reportUsedScanned.
  ///
  /// In en, this message translates to:
  /// **'Used (scanned)'**
  String get reportUsedScanned;

  /// No description provided for @reportVoided.
  ///
  /// In en, this message translates to:
  /// **'Voided'**
  String get reportVoided;

  /// No description provided for @reportConfirmedEntries.
  ///
  /// In en, this message translates to:
  /// **'Confirmed entries'**
  String get reportConfirmedEntries;

  /// No description provided for @reportCollected.
  ///
  /// In en, this message translates to:
  /// **'Revenue'**
  String get reportCollected;

  /// No description provided for @reportDistByType.
  ///
  /// In en, this message translates to:
  /// **'DISTRIBUTION BY TYPE'**
  String get reportDistByType;

  /// No description provided for @reportChartTicketsByType.
  ///
  /// In en, this message translates to:
  /// **'CHART: TICKETS BY TYPE'**
  String get reportChartTicketsByType;

  /// No description provided for @reportSalesByRrpp.
  ///
  /// In en, this message translates to:
  /// **'SALES BY PR / SELLER'**
  String get reportSalesByRrpp;

  /// No description provided for @reportChartRevenueByRrpp.
  ///
  /// In en, this message translates to:
  /// **'CHART: REVENUE BY PR'**
  String get reportChartRevenueByRrpp;

  /// No description provided for @reportChartTicketsByRrpp.
  ///
  /// In en, this message translates to:
  /// **'CHART: TICKETS BY PR'**
  String get reportChartTicketsByRrpp;

  /// No description provided for @reportEmissionByDay.
  ///
  /// In en, this message translates to:
  /// **'TICKET EMISSION BY DAY AND TYPE'**
  String get reportEmissionByDay;

  /// No description provided for @reportNoEmissionData.
  ///
  /// In en, this message translates to:
  /// **'No emission data'**
  String get reportNoEmissionData;

  /// No description provided for @reportScansByHour.
  ///
  /// In en, this message translates to:
  /// **'SCANS BY HOUR'**
  String get reportScansByHour;

  /// No description provided for @reportNoScanData.
  ///
  /// In en, this message translates to:
  /// **'No scan data'**
  String get reportNoScanData;

  /// No description provided for @reportScansByOperator.
  ///
  /// In en, this message translates to:
  /// **'SCANS BY OPERATOR'**
  String get reportScansByOperator;

  /// No description provided for @reportNoOperatorData.
  ///
  /// In en, this message translates to:
  /// **'No operator data'**
  String get reportNoOperatorData;

  /// No description provided for @reportDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'COMPLETE TICKET DETAIL'**
  String get reportDetailTitle;

  /// No description provided for @reportNoData.
  ///
  /// In en, this message translates to:
  /// **'No data'**
  String get reportNoData;

  /// No description provided for @reportPage.
  ///
  /// In en, this message translates to:
  /// **'Page {num}'**
  String reportPage(int num);

  /// No description provided for @reportSubject.
  ///
  /// In en, this message translates to:
  /// **'Report {name}'**
  String reportSubject(String name);

  /// No description provided for @reportSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get reportSystem;

  /// No description provided for @reportUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get reportUnknown;

  /// No description provided for @reportHeaderName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get reportHeaderName;

  /// No description provided for @reportHeaderDoc.
  ///
  /// In en, this message translates to:
  /// **'Doc'**
  String get reportHeaderDoc;

  /// No description provided for @reportHeaderType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get reportHeaderType;

  /// No description provided for @reportHeaderPrice.
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get reportHeaderPrice;

  /// No description provided for @reportHeaderStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get reportHeaderStatus;

  /// No description provided for @reportHeaderCreated.
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get reportHeaderCreated;

  /// No description provided for @reportHeaderSeller.
  ///
  /// In en, this message translates to:
  /// **'Seller'**
  String get reportHeaderSeller;

  /// No description provided for @reportHeaderQuantity.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get reportHeaderQuantity;

  /// No description provided for @reportHeaderPercent.
  ///
  /// In en, this message translates to:
  /// **'% of Total'**
  String get reportHeaderPercent;

  /// No description provided for @reportHeaderRrpp.
  ///
  /// In en, this message translates to:
  /// **'PR'**
  String get reportHeaderRrpp;

  /// No description provided for @reportHeaderTotal.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get reportHeaderTotal;

  /// No description provided for @reportHeaderValidCount.
  ///
  /// In en, this message translates to:
  /// **'Valid'**
  String get reportHeaderValidCount;

  /// No description provided for @reportHeaderRevenue.
  ///
  /// In en, this message translates to:
  /// **'Revenue'**
  String get reportHeaderRevenue;

  /// No description provided for @reportCatSale.
  ///
  /// In en, this message translates to:
  /// **'Sale'**
  String get reportCatSale;

  /// No description provided for @reportCatGuest.
  ///
  /// In en, this message translates to:
  /// **'Courtesy'**
  String get reportCatGuest;

  /// No description provided for @reportCatStaff.
  ///
  /// In en, this message translates to:
  /// **'Staff'**
  String get reportCatStaff;

  /// No description provided for @reportCatInvitation.
  ///
  /// In en, this message translates to:
  /// **'Invitation'**
  String get reportCatInvitation;

  /// No description provided for @reportStatusValid.
  ///
  /// In en, this message translates to:
  /// **'Valid'**
  String get reportStatusValid;

  /// No description provided for @reportStatusUsed.
  ///
  /// In en, this message translates to:
  /// **'Used'**
  String get reportStatusUsed;

  /// No description provided for @reportStatusVoid.
  ///
  /// In en, this message translates to:
  /// **'Voided'**
  String get reportStatusVoid;

  /// No description provided for @offlinePendingOps.
  ///
  /// In en, this message translates to:
  /// **'Offline mode. {count} pending operations.'**
  String offlinePendingOps(int count);

  /// No description provided for @offlineWillSync.
  ///
  /// In en, this message translates to:
  /// **'Offline mode. Will sync on reconnect.'**
  String get offlineWillSync;

  /// No description provided for @offlineOpsDropped.
  ///
  /// In en, this message translates to:
  /// **'{count} offline operation(s) could not be synced and were discarded.'**
  String offlineOpsDropped(int count);

  /// No description provided for @enablePromoPack.
  ///
  /// In en, this message translates to:
  /// **'Enable Promo Pack'**
  String get enablePromoPack;

  /// No description provided for @promoPackSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Creates a promotional ticket type with configurable price and quantity'**
  String get promoPackSubtitle;

  /// No description provided for @promoPrice.
  ///
  /// In en, this message translates to:
  /// **'Promo price'**
  String get promoPrice;

  /// No description provided for @promoQty.
  ///
  /// In en, this message translates to:
  /// **'Ticket quantity'**
  String get promoQty;

  /// No description provided for @ticketTypePromo.
  ///
  /// In en, this message translates to:
  /// **'Promo'**
  String get ticketTypePromo;

  /// No description provided for @promoTicketsCreated.
  ///
  /// In en, this message translates to:
  /// **'{count} promo tickets created successfully'**
  String promoTicketsCreated(int count);

  /// No description provided for @promoCreatingTickets.
  ///
  /// In en, this message translates to:
  /// **'Creating {current} of {total}...'**
  String promoCreatingTickets(int current, int total);

  /// No description provided for @reportCatPromo.
  ///
  /// In en, this message translates to:
  /// **'Promo'**
  String get reportCatPromo;

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// No description provided for @profileSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your account, security and preferences'**
  String get profileSubtitle;

  /// No description provided for @accountData.
  ///
  /// In en, this message translates to:
  /// **'Account details'**
  String get accountData;

  /// No description provided for @security.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get security;

  /// No description provided for @preferences.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get preferences;

  /// No description provided for @organization.
  ///
  /// In en, this message translates to:
  /// **'Organization'**
  String get organization;

  /// No description provided for @profilePhoto.
  ///
  /// In en, this message translates to:
  /// **'Profile photo'**
  String get profilePhoto;

  /// No description provided for @changePhoto.
  ///
  /// In en, this message translates to:
  /// **'Change photo'**
  String get changePhoto;

  /// No description provided for @removePhoto.
  ///
  /// In en, this message translates to:
  /// **'Remove photo'**
  String get removePhoto;

  /// No description provided for @phone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get phone;

  /// No description provided for @phoneOptional.
  ///
  /// In en, this message translates to:
  /// **'Phone (optional)'**
  String get phoneOptional;

  /// No description provided for @emailCannotChange.
  ///
  /// In en, this message translates to:
  /// **'Email cannot be changed'**
  String get emailCannotChange;

  /// No description provided for @profileSaved.
  ///
  /// In en, this message translates to:
  /// **'Profile updated'**
  String get profileSaved;

  /// No description provided for @profileSaveError.
  ///
  /// In en, this message translates to:
  /// **'Could not save profile'**
  String get profileSaveError;

  /// No description provided for @photoTooLarge.
  ///
  /// In en, this message translates to:
  /// **'Image exceeds 2 MB'**
  String get photoTooLarge;

  /// No description provided for @photoUploadError.
  ///
  /// In en, this message translates to:
  /// **'Could not upload photo'**
  String get photoUploadError;

  /// No description provided for @passwordChangeError.
  ///
  /// In en, this message translates to:
  /// **'Could not change password'**
  String get passwordChangeError;

  /// No description provided for @signOutOtherSessions.
  ///
  /// In en, this message translates to:
  /// **'Sign out other devices'**
  String get signOutOtherSessions;

  /// No description provided for @signOutOtherSessionsHint.
  ///
  /// In en, this message translates to:
  /// **'Useful if you lost a phone or shared your account'**
  String get signOutOtherSessionsHint;

  /// No description provided for @otherSessionsClosed.
  ///
  /// In en, this message translates to:
  /// **'Other sessions were closed'**
  String get otherSessionsClosed;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @orgCommercialName.
  ///
  /// In en, this message translates to:
  /// **'Trade name'**
  String get orgCommercialName;

  /// No description provided for @orgLegalName.
  ///
  /// In en, this message translates to:
  /// **'Legal name'**
  String get orgLegalName;

  /// No description provided for @orgTaxId.
  ///
  /// In en, this message translates to:
  /// **'Tax ID'**
  String get orgTaxId;

  /// No description provided for @orgAddress.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get orgAddress;

  /// No description provided for @orgContactEmail.
  ///
  /// In en, this message translates to:
  /// **'Contact email'**
  String get orgContactEmail;

  /// No description provided for @orgContactPhone.
  ///
  /// In en, this message translates to:
  /// **'Contact phone'**
  String get orgContactPhone;

  /// No description provided for @orgLogo.
  ///
  /// In en, this message translates to:
  /// **'Logo'**
  String get orgLogo;

  /// No description provided for @orgSaved.
  ///
  /// In en, this message translates to:
  /// **'Organization updated'**
  String get orgSaved;

  /// No description provided for @orgSaveError.
  ///
  /// In en, this message translates to:
  /// **'Could not save organization'**
  String get orgSaveError;

  /// No description provided for @orgAdminOnly.
  ///
  /// In en, this message translates to:
  /// **'Only an administrator can edit these details'**
  String get orgAdminOnly;

  /// No description provided for @orgBillingHint.
  ///
  /// In en, this message translates to:
  /// **'These details are used for billing'**
  String get orgBillingHint;

  /// No description provided for @showPassword.
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get showPassword;

  /// No description provided for @hidePassword.
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get hidePassword;

  /// No description provided for @eventArtwork.
  ///
  /// In en, this message translates to:
  /// **'Event artwork'**
  String get eventArtwork;

  /// No description provided for @eventArtworkHint.
  ///
  /// In en, this message translates to:
  /// **'Shown next to the QR code in the ticket email'**
  String get eventArtworkHint;

  /// No description provided for @uploadImage.
  ///
  /// In en, this message translates to:
  /// **'Upload image'**
  String get uploadImage;

  /// No description provided for @removeImage.
  ///
  /// In en, this message translates to:
  /// **'Remove image'**
  String get removeImage;

  /// No description provided for @imageTooLarge.
  ///
  /// In en, this message translates to:
  /// **'Image exceeds 2 MB'**
  String get imageTooLarge;

  /// No description provided for @imageUploadError.
  ///
  /// In en, this message translates to:
  /// **'Could not upload image'**
  String get imageUploadError;

  /// No description provided for @selectEventFirstTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose an event first'**
  String get selectEventFirstTitle;

  /// No description provided for @selectEventFirstBody.
  ///
  /// In en, this message translates to:
  /// **'The team is assigned per event: each promoter and door device works on a specific event.'**
  String get selectEventFirstBody;

  /// No description provided for @goToEvents.
  ///
  /// In en, this message translates to:
  /// **'Go to my events'**
  String get goToEvents;

  /// No description provided for @noEventsYet.
  ///
  /// In en, this message translates to:
  /// **'No events yet'**
  String get noEventsYet;

  /// No description provided for @noEventsYetBody.
  ///
  /// In en, this message translates to:
  /// **'An event is the starting point: tickets, team and scanner all work on one.'**
  String get noEventsYetBody;

  /// No description provided for @createFirstEvent.
  ///
  /// In en, this message translates to:
  /// **'Create my first event'**
  String get createFirstEvent;

  /// No description provided for @noTicketsYet.
  ///
  /// In en, this message translates to:
  /// **'No tickets yet'**
  String get noTicketsYet;

  /// No description provided for @noTicketsYetBody.
  ///
  /// In en, this message translates to:
  /// **'Once you issue a ticket it will show up here, with its QR and status.'**
  String get noTicketsYetBody;

  /// No description provided for @createFirstTicket.
  ///
  /// In en, this message translates to:
  /// **'Create a ticket'**
  String get createFirstTicket;

  /// No description provided for @superAdmin.
  ///
  /// In en, this message translates to:
  /// **'Super Admin'**
  String get superAdmin;

  /// No description provided for @tenants.
  ///
  /// In en, this message translates to:
  /// **'Organizations'**
  String get tenants;

  /// No description provided for @tenantsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Every organization in the system'**
  String get tenantsSubtitle;

  /// No description provided for @searchTenant.
  ///
  /// In en, this message translates to:
  /// **'Search organization'**
  String get searchTenant;

  /// No description provided for @tenantActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get tenantActive;

  /// No description provided for @tenantSuspended.
  ///
  /// In en, this message translates to:
  /// **'Suspended'**
  String get tenantSuspended;

  /// No description provided for @tenantSuspend.
  ///
  /// In en, this message translates to:
  /// **'Suspend'**
  String get tenantSuspend;

  /// No description provided for @tenantReactivate.
  ///
  /// In en, this message translates to:
  /// **'Reactivate'**
  String get tenantReactivate;

  /// No description provided for @tenantSuspendReason.
  ///
  /// In en, this message translates to:
  /// **'Reason for suspension'**
  String get tenantSuspendReason;

  /// No description provided for @tenantSuspendWarning.
  ///
  /// In en, this message translates to:
  /// **'The organization loses access until you reactivate it. Door staff will not be able to scan.'**
  String get tenantSuspendWarning;

  /// No description provided for @subscription.
  ///
  /// In en, this message translates to:
  /// **'Subscription'**
  String get subscription;

  /// No description provided for @plan.
  ///
  /// In en, this message translates to:
  /// **'Plan'**
  String get plan;

  /// No description provided for @expiresOn.
  ///
  /// In en, this message translates to:
  /// **'Expires on'**
  String get expiresOn;

  /// No description provided for @noExpiry.
  ///
  /// In en, this message translates to:
  /// **'No expiry'**
  String get noExpiry;

  /// No description provided for @expiresInDays.
  ///
  /// In en, this message translates to:
  /// **'Expires in {days} days'**
  String expiresInDays(int days);

  /// No description provided for @expiredDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'Expired {days} days ago'**
  String expiredDaysAgo(int days);

  /// No description provided for @extendSubscription.
  ///
  /// In en, this message translates to:
  /// **'Change subscription'**
  String get extendSubscription;

  /// No description provided for @viewAsTenant.
  ///
  /// In en, this message translates to:
  /// **'View as this client'**
  String get viewAsTenant;

  /// No description provided for @viewAsTenantWarning.
  ///
  /// In en, this message translates to:
  /// **'You will see the app with this organization\'s data. It is recorded in the audit log.'**
  String get viewAsTenantWarning;

  /// No description provided for @auditLog.
  ///
  /// In en, this message translates to:
  /// **'Audit log'**
  String get auditLog;

  /// No description provided for @noTenants.
  ///
  /// In en, this message translates to:
  /// **'No organizations yet'**
  String get noTenants;

  /// No description provided for @tenantUsers.
  ///
  /// In en, this message translates to:
  /// **'Users'**
  String get tenantUsers;

  /// No description provided for @tenantEvents.
  ///
  /// In en, this message translates to:
  /// **'Events'**
  String get tenantEvents;

  /// No description provided for @tenantTickets.
  ///
  /// In en, this message translates to:
  /// **'Tickets'**
  String get tenantTickets;

  /// No description provided for @orgSuspendedTitle.
  ///
  /// In en, this message translates to:
  /// **'Organization suspended'**
  String get orgSuspendedTitle;

  /// No description provided for @orgSuspendedBody.
  ///
  /// In en, this message translates to:
  /// **'Access is suspended. Contact the system administrator to restore it.'**
  String get orgSuspendedBody;

  /// No description provided for @billingCountry.
  ///
  /// In en, this message translates to:
  /// **'Billing country'**
  String get billingCountry;

  /// No description provided for @billingCountryHelp.
  ///
  /// In en, this message translates to:
  /// **'We use it to charge your subscription. You can change it later.'**
  String get billingCountryHelp;

  /// No description provided for @subscriptionExpired.
  ///
  /// In en, this message translates to:
  /// **'Your subscription expired. You can still view and validate your tickets, but not create new events.'**
  String get subscriptionExpired;

  /// No description provided for @organizationSuspended.
  ///
  /// In en, this message translates to:
  /// **'Your account is suspended. Contact us to reactivate it.'**
  String get organizationSuspended;

  /// No description provided for @subscribeNow.
  ///
  /// In en, this message translates to:
  /// **'Activate subscription'**
  String get subscribeNow;

  /// No description provided for @planMonthlyPrice.
  ///
  /// In en, this message translates to:
  /// **'USD 25 per month'**
  String get planMonthlyPrice;

  /// No description provided for @planAnnualPrice.
  ///
  /// In en, this message translates to:
  /// **'USD 250 per year (2 months free)'**
  String get planAnnualPrice;

  /// No description provided for @subscriptionLinkFailed.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t generate the payment link. Please try again in a moment.'**
  String get subscriptionLinkFailed;

  /// No description provided for @freeTicketsTitle.
  ///
  /// In en, this message translates to:
  /// **'Free tickets'**
  String get freeTicketsTitle;

  /// No description provided for @freeTicketsUsedOf.
  ///
  /// In en, this message translates to:
  /// **'{used} of {total} used'**
  String freeTicketsUsedOf(int used, int total);

  /// No description provided for @freeTicketsLeft.
  ///
  /// In en, this message translates to:
  /// **'You have {count} free tickets left'**
  String freeTicketsLeft(int count);

  /// No description provided for @freeTicketsExhausted.
  ///
  /// In en, this message translates to:
  /// **'You used your free tickets. Activate the subscription to keep issuing.'**
  String get freeTicketsExhausted;

  /// No description provided for @freeTicketsNote.
  ///
  /// In en, this message translates to:
  /// **'Voiding a ticket does not give the quota back.'**
  String get freeTicketsNote;

  /// No description provided for @choosePlan.
  ///
  /// In en, this message translates to:
  /// **'Choose your plan'**
  String get choosePlan;

  /// No description provided for @planUnlimitedNote.
  ///
  /// In en, this message translates to:
  /// **'Unlimited tickets, unlimited events, your whole team.'**
  String get planUnlimitedNote;

  /// No description provided for @planAnnualSaving.
  ///
  /// In en, this message translates to:
  /// **'Save 2 months'**
  String get planAnnualSaving;

  /// No description provided for @paymentHandledBy.
  ///
  /// In en, this message translates to:
  /// **'Payment is processed by dLocal. Opens in a new tab.'**
  String get paymentHandledBy;

  /// No description provided for @statusActive.
  ///
  /// In en, this message translates to:
  /// **'Subscription active'**
  String get statusActive;

  /// No description provided for @statusTrial.
  ///
  /// In en, this message translates to:
  /// **'Free plan'**
  String get statusTrial;

  /// No description provided for @statusExpired.
  ///
  /// In en, this message translates to:
  /// **'Subscription expired'**
  String get statusExpired;

  /// No description provided for @statusSuspended.
  ///
  /// In en, this message translates to:
  /// **'Account suspended'**
  String get statusSuspended;

  /// No description provided for @statusQuotaExhausted.
  ///
  /// In en, this message translates to:
  /// **'No free tickets left'**
  String get statusQuotaExhausted;

  /// No description provided for @renewsOn.
  ///
  /// In en, this message translates to:
  /// **'Valid until {date}'**
  String renewsOn(String date);

  /// No description provided for @errorGeneric.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t load this information.'**
  String get errorGeneric;

  /// No description provided for @updateAvailable.
  ///
  /// In en, this message translates to:
  /// **'A new version is available. Tap \"Update\" below.'**
  String get updateAvailable;

  /// No description provided for @upToDate.
  ///
  /// In en, this message translates to:
  /// **'Data reloaded. You\'re on the latest version.'**
  String get upToDate;

  /// No description provided for @wrongEvent.
  ///
  /// In en, this message translates to:
  /// **'WRONG EVENT'**
  String get wrongEvent;

  /// No description provided for @ticketBelongsTo.
  ///
  /// In en, this message translates to:
  /// **'THIS TICKET IS FOR:'**
  String get ticketBelongsTo;

  /// No description provided for @cancelSubscription.
  ///
  /// In en, this message translates to:
  /// **'Cancel subscription'**
  String get cancelSubscription;

  /// No description provided for @cancelSubscriptionExplain.
  ///
  /// In en, this message translates to:
  /// **'We stop charging you. You keep access until {fecha}, which is what you already paid for.'**
  String cancelSubscriptionExplain(String fecha);

  /// No description provided for @cancelSubscriptionConfirm.
  ///
  /// In en, this message translates to:
  /// **'Cancel billing?'**
  String get cancelSubscriptionConfirm;

  /// No description provided for @cancelSubscriptionConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'You won\'t be charged again. Everything keeps working until {fecha}, then the account moves to the free plan. You can subscribe again any time.'**
  String cancelSubscriptionConfirmBody(String fecha);

  /// No description provided for @cancelSubscriptionAction.
  ///
  /// In en, this message translates to:
  /// **'Yes, cancel'**
  String get cancelSubscriptionAction;

  /// No description provided for @cancelSubscriptionDone.
  ///
  /// In en, this message translates to:
  /// **'Subscription cancelled. You have access until {fecha}.'**
  String cancelSubscriptionDone(String fecha);

  /// No description provided for @subscriptionCancelled.
  ///
  /// In en, this message translates to:
  /// **'Subscription cancelled'**
  String get subscriptionCancelled;

  /// No description provided for @subscriptionCancelledUntil.
  ///
  /// In en, this message translates to:
  /// **'Access until {fecha}. It will not renew.'**
  String subscriptionCancelledUntil(String fecha);

  /// No description provided for @resubscribe.
  ///
  /// In en, this message translates to:
  /// **'Subscribe again'**
  String get resubscribe;

  /// No description provided for @deleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete my account'**
  String get deleteAccount;

  /// No description provided for @deleteAccountHint.
  ///
  /// In en, this message translates to:
  /// **'Deletes your account. This cannot be undone'**
  String get deleteAccountHint;

  /// No description provided for @deleteAccountTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get deleteAccountTitle;

  /// No description provided for @deleteAccountMember.
  ///
  /// In en, this message translates to:
  /// **'Your account and access are deleted. The organization and its data stay as they are.'**
  String get deleteAccountMember;

  /// No description provided for @deleteAccountOwner.
  ///
  /// In en, this message translates to:
  /// **'You own {org}. The ENTIRE organization is deleted and cannot be recovered:'**
  String deleteAccountOwner(String org);

  /// No description provided for @deleteAccountOwnerItems.
  ///
  /// In en, this message translates to:
  /// **'{eventos} events · {tickets} tickets · {escaneos} scans · {miembros} team accounts'**
  String deleteAccountOwnerItems(
    String eventos,
    String tickets,
    String escaneos,
    String miembros,
  );

  /// No description provided for @deleteAccountTypeName.
  ///
  /// In en, this message translates to:
  /// **'Type {org} to confirm'**
  String deleteAccountTypeName(String org);

  /// No description provided for @deleteAccountAction.
  ///
  /// In en, this message translates to:
  /// **'Delete permanently'**
  String get deleteAccountAction;

  /// No description provided for @deleteAccountDone.
  ///
  /// In en, this message translates to:
  /// **'Account deleted.'**
  String get deleteAccountDone;

  /// No description provided for @deleteAccountNameMismatch.
  ///
  /// In en, this message translates to:
  /// **'The name doesn\'t match.'**
  String get deleteAccountNameMismatch;

  /// No description provided for @deleteAccountSuperadmin.
  ///
  /// In en, this message translates to:
  /// **'A super-admin account can\'t be deleted from here. Move the role to another account first.'**
  String get deleteAccountSuperadmin;

  /// Settings entry to install the PWA
  ///
  /// In en, this message translates to:
  /// **'Install app'**
  String get installApp;

  /// Subtitle of the install entry
  ///
  /// In en, this message translates to:
  /// **'Add it to your home screen and open it like any other app'**
  String get installAppDesc;

  /// Shown after the browser install dialog opens
  ///
  /// In en, this message translates to:
  /// **'Follow your browser to finish installing'**
  String get installOpened;

  /// iPhone has no install dialog; it is manual from the Share sheet
  ///
  /// In en, this message translates to:
  /// **'On iPhone: Share button, then \"Add to Home Screen\"'**
  String get installIOS;

  /// The browser has not fired beforeinstallprompt yet
  ///
  /// In en, this message translates to:
  /// **'Your browser is not offering it yet. Use it for a moment and try again.'**
  String get installNotReady;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'es', 'pt'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'pt':
      return AppLocalizationsPt();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
