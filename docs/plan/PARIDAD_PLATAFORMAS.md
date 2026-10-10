# Matriz inicial de paridad Swift ↔ API ↔ Flutter

Generada desde el árbol SwiftUI actual y `contracts/openapi.json`. La existencia de un endpoint no prueba que su flujo móvil esté aceptado. Marcar cada fila al portar y probar, no al crear la pantalla.

## Vistas Swift existentes

| Vista | Archivo origen | Dominio/ruta API a revisar | Estado Flutter |
|---|---|---|---|
| `RootContentView` | `DLCGasolineras/App/DLCGasolinerasApp.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `RemoteSessionHomeView` | `DLCGasolineras/App/DLCGasolinerasApp.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `RemoteBranchDashboardView` | `DLCGasolineras/App/DLCGasolinerasApp.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `RemoteIncidentDashboardDetail` | `DLCGasolineras/App/DLCGasolinerasApp.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `RemoteAnomalyReviewSheet` | `DLCGasolineras/App/DLCGasolinerasApp.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `RemoteNetworkDashboardView` | `DLCGasolineras/App/DLCGasolinerasApp.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `RemoteReportCenterView` | `DLCGasolineras/App/DLCGasolinerasApp.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `LoginView` | `DLCGasolineras/Views/Auth/LoginView.swift` | auth login/me/capabilities | pendiente |
| `BranchDashboardView` | `DLCGasolineras/Views/BranchManager/BranchDashboardView.swift` | metrics/branches/{branchId}/dashboard; cuts; inventory; incidents | pendiente |
| `BranchManagerTabView` | `DLCGasolineras/Views/BranchManager/BranchManagerTabView.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `CutFormView` | `DLCGasolineras/Views/BranchManager/CutFormView.swift` | cuts/{cutId}/meters/tanks | pendiente |
| `CutSummaryView` | `DLCGasolineras/Views/BranchManager/CutSummaryView.swift` | cuts/{cutId}/closure | pendiente |
| `CutsView` | `DLCGasolineras/Views/BranchManager/CutsView.swift` | cuts; reconciliation; close | pendiente |
| `CutScheduleCard` | `DLCGasolineras/Views/BranchManager/CutsView.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `RemoteCutsDirectoryView` | `DLCGasolineras/Views/BranchManager/CutsView.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `RemoteCutScheduleCard` | `DLCGasolineras/Views/BranchManager/CutsView.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `CutProgressOrb` | `DLCGasolineras/Views/BranchManager/CutsView.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `RemoteCutDetailView` | `DLCGasolineras/Views/BranchManager/CutsView.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `RemoteCutNozzleEntry` | `DLCGasolineras/Views/BranchManager/CutsView.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `RemoteCutTankEntry` | `DLCGasolineras/Views/BranchManager/CutsView.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `PumpRegistrationView` | `DLCGasolineras/Views/BranchManager/PumpRegistrationView.swift` | dispensers create; nozzles; connection | pendiente |
| `PumpsOverviewView` | `DLCGasolineras/Views/BranchManager/PumpsOverviewView.swift` | dispensers; meter-readings; history | pendiente |
| `HistoryCutRow` | `DLCGasolineras/Views/BranchManager/PumpsOverviewView.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `CutHistoryDetailView` | `DLCGasolineras/Views/BranchManager/PumpsOverviewView.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `RemotePumpsOverviewView` | `DLCGasolineras/Views/BranchManager/PumpsOverviewView.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `RemoteDispenserDetailView` | `DLCGasolineras/Views/BranchManager/PumpsOverviewView.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `RemoteMeterCaptureSheet` | `DLCGasolineras/Views/BranchManager/PumpsOverviewView.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `RemoteDispenseFlowSheet` | `DLCGasolineras/Views/BranchManager/PumpsOverviewView.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `RemoteDispenseQueueView` | `DLCGasolineras/Views/BranchManager/PumpsOverviewView.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `RemoteFuelSaleContent` | `DLCGasolineras/Views/BranchManager/PumpsOverviewView.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `RemoteFuelSalesView` | `DLCGasolineras/Views/BranchManager/PumpsOverviewView.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `RemotePrepaymentCollectionPanel` | `DLCGasolineras/Views/BranchManager/PumpsOverviewView.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `RemotePrepaymentCollectSheet` | `DLCGasolineras/Views/BranchManager/PumpsOverviewView.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `RemotePrepaymentsView` | `DLCGasolineras/Views/BranchManager/PumpsOverviewView.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `RemotePrepaymentAllocationSheet` | `DLCGasolineras/Views/BranchManager/PumpsOverviewView.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `RemotePrepaymentRefundActionSheet` | `DLCGasolineras/Views/BranchManager/PumpsOverviewView.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `RemoteFuelSaleDetailView` | `DLCGasolineras/Views/BranchManager/PumpsOverviewView.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `RemoteSalePaymentsPanel` | `DLCGasolineras/Views/BranchManager/PumpsOverviewView.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `RemoteSaleRefundPanel` | `DLCGasolineras/Views/BranchManager/PumpsOverviewView.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `RemoteRefundRequestSheet` | `DLCGasolineras/Views/BranchManager/PumpsOverviewView.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `RemoteRefundDecisionSheet` | `DLCGasolineras/Views/BranchManager/PumpsOverviewView.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `RemoteRefundExecutionSheet` | `DLCGasolineras/Views/BranchManager/PumpsOverviewView.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `RemotePaymentCollectionSheet` | `DLCGasolineras/Views/BranchManager/PumpsOverviewView.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `RemotePaymentResolutionSheet` | `DLCGasolineras/Views/BranchManager/PumpsOverviewView.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `RemoteFuelTaxPoliciesView` | `DLCGasolineras/Views/BranchManager/PumpsOverviewView.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `RemoteFuelTaxProposalView` | `DLCGasolineras/Views/BranchManager/PumpsOverviewView.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `PumpsStatusView` | `DLCGasolineras/Views/BranchManager/PumpsStatusView.swift` | dispensers status; availability; asset-blocks | pendiente |
| `PumpStatusRow` | `DLCGasolineras/Views/BranchManager/PumpsStatusView.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `RemotePOSCatalogView` | `DLCGasolineras/Views/BranchManager/RemotePOSViews.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `RemoteCombinedReceiptComposer` | `DLCGasolineras/Views/BranchManager/RemotePOSViews.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `RemotePOSProductDetailView` | `DLCGasolineras/Views/BranchManager/RemotePOSViews.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `RemotePOSOfferEditor` | `DLCGasolineras/Views/BranchManager/RemotePOSViews.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `RemotePOSReceiptEditor` | `DLCGasolineras/Views/BranchManager/RemotePOSViews.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `RemotePOSBasketView` | `DLCGasolineras/Views/BranchManager/RemotePOSViews.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `RemoteCashCenterView` | `DLCGasolineras/Views/BranchManager/RemotePOSViews.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `RemoteCashSessionView` | `DLCGasolineras/Views/BranchManager/RemotePOSViews.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `CashMetricPill` | `DLCGasolineras/Views/BranchManager/RemotePOSViews.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `CashReviewSummary` | `DLCGasolineras/Views/BranchManager/RemotePOSViews.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `RemoteCashVarianceDecisionSheet` | `DLCGasolineras/Views/BranchManager/RemotePOSViews.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `RemoteCashRegisterSheet` | `DLCGasolineras/Views/BranchManager/RemotePOSViews.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `RemoteCashOpenSheet` | `DLCGasolineras/Views/BranchManager/RemotePOSViews.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `RemoteCashMovementSheet` | `DLCGasolineras/Views/BranchManager/RemotePOSViews.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `RemoteCashCloseSheet` | `DLCGasolineras/Views/BranchManager/RemotePOSViews.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `BranchDetailView` | `DLCGasolineras/Views/GeneralManager/BranchDetailView.swift` | branches/{branchId}; configuration/readiness | pendiente |
| `BranchesView` | `DLCGasolineras/Views/GeneralManager/BranchesView.swift` | branches list/detail | pendiente |
| `RemoteBranchesDirectoryView` | `DLCGasolineras/Views/GeneralManager/BranchesView.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `RemoteBranchOnboardingView` | `DLCGasolineras/Views/GeneralManager/BranchesView.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `RemoteFuelOfferSetupView` | `DLCGasolineras/Views/GeneralManager/BranchesView.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `RemoteFuelProductCreateView` | `DLCGasolineras/Views/GeneralManager/BranchesView.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `RemoteBranchStaffSetupView` | `DLCGasolineras/Views/GeneralManager/BranchesView.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `RemoteBranchEmployeeCreateView` | `DLCGasolineras/Views/GeneralManager/BranchesView.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `RemoteBranchPriceSetupView` | `DLCGasolineras/Views/GeneralManager/BranchesView.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `RemoteFuelPriceProposalCreateView` | `DLCGasolineras/Views/GeneralManager/BranchesView.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `RemoteBranchDetailView` | `DLCGasolineras/Views/GeneralManager/BranchesView.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `BranchCard` | `DLCGasolineras/Views/GeneralManager/BranchesView.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `RemoteTanksDirectoryView` | `DLCGasolineras/Views/GeneralManager/BranchesView.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `RemoteTankDetailView` | `DLCGasolineras/Views/GeneralManager/BranchesView.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `GeneralDashboardView` | `DLCGasolineras/Views/GeneralManager/GeneralDashboardView.swift` | metrics/network/dashboard; branches | pendiente |
| `GeneralManagerTabView` | `DLCGasolineras/Views/GeneralManager/GeneralManagerTabView.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `ManagersView` | `DLCGasolineras/Views/GeneralManager/ManagersView.swift` | users; users assignments | pendiente |
| `ManagerAssignmentCard` | `DLCGasolineras/Views/GeneralManager/ManagersView.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `NewManagerView` | `DLCGasolineras/Views/GeneralManager/ManagersView.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `EditManagerView` | `DLCGasolineras/Views/GeneralManager/ManagersView.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `ResetManagerPasswordView` | `DLCGasolineras/Views/GeneralManager/ManagersView.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `NewBranchView` | `DLCGasolineras/Views/GeneralManager/NewBranchView.swift` | branches create/onboarding/activate | pendiente |
| `HeaderView` | `DLCGasolineras/Views/Shared/HeaderView.swift` | shared shell and session identity | pendiente |
| `AccountView` | `DLCGasolineras/Views/Shared/HeaderView.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `StatusBadge` | `DLCGasolineras/Views/Shared/InventoryComponents.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `FuelProgressRow` | `DLCGasolineras/Views/Shared/InventoryComponents.swift` | metrics dashboard inventory model | pendiente |
| `FuelTankDetailView` | `DLCGasolineras/Views/Shared/InventoryComponents.swift` | tanks/{tankId}; inventory/movements | pendiente |
| `SalesCard` | `DLCGasolineras/Views/Shared/InventoryComponents.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `LogoView` | `DLCGasolineras/Views/Shared/LogoView.swift` | brand assets | pendiente |
| `OperationsRootView` | `DLCGasolineras/Views/Shared/OperationsViews.swift` | branches/{branchId}/<module>; review action routes | pendiente |
| `NetworkManagementHomeView` | `DLCGasolineras/Views/Shared/OperationsViews.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `BranchStoreHomeView` | `DLCGasolineras/Views/Shared/OperationsViews.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `TeamOperationsHomeView` | `DLCGasolineras/Views/Shared/OperationsViews.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `OperationsLinkRow` | `DLCGasolineras/Views/Shared/OperationsViews.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `ProductCatalogView` | `DLCGasolineras/Views/Shared/OperationsViews.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `ProductFormView` | `DLCGasolineras/Views/Shared/OperationsViews.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `SuppliersListView` | `DLCGasolineras/Views/Shared/OperationsViews.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `SupplierFormView` | `DLCGasolineras/Views/Shared/OperationsViews.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `StoreInventoryView` | `DLCGasolineras/Views/Shared/OperationsViews.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `StoreLotListView` | `DLCGasolineras/Views/Shared/OperationsViews.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `ReceiveStoreLotView` | `DLCGasolineras/Views/Shared/OperationsViews.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `StoreLotAdjustmentView` | `DLCGasolineras/Views/Shared/OperationsViews.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `StorePOSView` | `DLCGasolineras/Views/Shared/OperationsViews.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `StoreSalesHistoryView` | `DLCGasolineras/Views/Shared/OperationsViews.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `StoreSaleDetailView` | `DLCGasolineras/Views/Shared/OperationsViews.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `VoidStoreSaleView` | `DLCGasolineras/Views/Shared/OperationsViews.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `StaffManagementView` | `DLCGasolineras/Views/Shared/OperationsViews.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `StaffFormView` | `DLCGasolineras/Views/Shared/OperationsViews.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `ShiftAssignmentFormView` | `DLCGasolineras/Views/Shared/OperationsViews.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `EquipmentMaintenanceView` | `DLCGasolineras/Views/Shared/OperationsViews.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `EquipmentFormView` | `DLCGasolineras/Views/Shared/OperationsViews.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `EquipmentDetailsFormView` | `DLCGasolineras/Views/Shared/OperationsViews.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `MaintenanceOrderFormView` | `DLCGasolineras/Views/Shared/OperationsViews.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `MaintenanceOrderEditView` | `DLCGasolineras/Views/Shared/OperationsViews.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `EditBranchView` | `DLCGasolineras/Views/Shared/OperationsViews.swift` | Revisar navegación/casos en el archivo de origen | pendiente |
| `CardSurface` | `DLCGasolineras/Views/Shared/Theme.swift` | Revisar navegación/casos en el archivo de origen | pendiente |

## ViewModels y modelos de dominio

ViewModels que concentran estado y llamadas:
- `AuthViewModel` — `DLCGasolineras/ViewModels/AuthViewModel.swift`
- `BranchManagerViewModel` — `DLCGasolineras/ViewModels/BranchManagerViewModel.swift`
- `RemoteNozzleSnapshot` — `DLCGasolineras/ViewModels/BranchManagerViewModel.swift`
- `RemoteDispenserSnapshot` — `DLCGasolineras/ViewModels/BranchManagerViewModel.swift`
- `RemotePumpsViewModel` — `DLCGasolineras/ViewModels/BranchManagerViewModel.swift`
- `RemoteCutsDirectoryViewModel` — `DLCGasolineras/ViewModels/BranchManagerViewModel.swift`
- `RemoteCutWorkflowViewModel` — `DLCGasolineras/ViewModels/BranchManagerViewModel.swift`
- `RemoteTankSnapshot` — `DLCGasolineras/ViewModels/BranchManagerViewModel.swift`
- `RemoteTanksViewModel` — `DLCGasolineras/ViewModels/BranchManagerViewModel.swift`
- `CutFlowViewModel` — `DLCGasolineras/ViewModels/CutFlowViewModel.swift`
- `BranchTankAlert` — `DLCGasolineras/ViewModels/GeneralManagerViewModel.swift`
- `GeneralManagerViewModel` — `DLCGasolineras/ViewModels/GeneralManagerViewModel.swift`
- `RemoteBranchesViewModel` — `DLCGasolineras/ViewModels/GeneralManagerViewModel.swift`
- `StoreStockAlert` — `DLCGasolineras/ViewModels/OperationsViewModel.swift`
- `OperationsViewModel` — `DLCGasolineras/ViewModels/OperationsViewModel.swift`
- `RemotePOSCartLine` — `DLCGasolineras/ViewModels/RemotePOSViewModel.swift`
- `RemotePOSViewModel` — `DLCGasolineras/ViewModels/RemotePOSViewModel.swift`
- `RemotePOSLotsViewModel` — `DLCGasolineras/ViewModels/RemotePOSViewModel.swift`
- `RemoteCombinedReceiptViewModel` — `DLCGasolineras/ViewModels/RemotePOSViewModel.swift`
- `RemoteCashViewModel` — `DLCGasolineras/ViewModels/RemotePOSViewModel.swift`
- `RemotePaymentViewModel` — `DLCGasolineras/ViewModels/RemotePOSViewModel.swift`
- `RemoteRefundViewModel` — `DLCGasolineras/ViewModels/RemotePOSViewModel.swift`
- `RemotePrepaymentRefundRequestBody` — `DLCGasolineras/ViewModels/RemotePOSViewModel.swift`
- `RemotePrepaymentRefundViewModel` — `DLCGasolineras/ViewModels/RemotePOSViewModel.swift`

Modelos/types Swift a comparar con DTO y vectores API:
- `FuelType` — `DLCGasolineras/Models/DomainModels.swift`
- `UserRole` — `DLCGasolineras/Models/DomainModels.swift`
- `AppUser` — `DLCGasolineras/Models/DomainModels.swift`
- `InventoryStatus` — `DLCGasolineras/Models/DomainModels.swift`
- `FuelTank` — `DLCGasolineras/Models/DomainModels.swift`
- `Branch` — `DLCGasolineras/Models/DomainModels.swift`
- `FuelReading` — `DLCGasolineras/Models/DomainModels.swift`
- `PumpReading` — `DLCGasolineras/Models/DomainModels.swift`
- `CutType` — `DLCGasolineras/Models/DomainModels.swift`
- `MovementKind` — `DLCGasolineras/Models/DomainModels.swift`
- `LossCause` — `DLCGasolineras/Models/DomainModels.swift`
- `FuelMovement` — `DLCGasolineras/Models/DomainModels.swift`
- `DailyCut` — `DLCGasolineras/Models/DomainModels.swift`
- `MetricsPeriod` — `DLCGasolineras/Models/DomainModels.swift`
- `FuelMetric` — `DLCGasolineras/Models/DomainModels.swift`
- `StoreCategory` — `DLCGasolineras/Models/DomainModels.swift`
- `StoreProduct` — `DLCGasolineras/Models/DomainModels.swift`
- `SupplierScope` — `DLCGasolineras/Models/DomainModels.swift`
- `StoreSupplier` — `DLCGasolineras/Models/DomainModels.swift`
- `StoreLot` — `DLCGasolineras/Models/DomainModels.swift`
- `StockMovementKind` — `DLCGasolineras/Models/DomainModels.swift`
- `StockMovement` — `DLCGasolineras/Models/DomainModels.swift`
- `SaleLineLotAllocation` — `DLCGasolineras/Models/DomainModels.swift`
- `StoreSaleLine` — `DLCGasolineras/Models/DomainModels.swift`
- `PaymentMethod` — `DLCGasolineras/Models/DomainModels.swift`
- `SaleStatus` — `DLCGasolineras/Models/DomainModels.swift`
- `StoreSale` — `DLCGasolineras/Models/DomainModels.swift`
- `StaffStatus` — `DLCGasolineras/Models/DomainModels.swift`
- `StaffMember` — `DLCGasolineras/Models/DomainModels.swift`
- `WorkShift` — `DLCGasolineras/Models/DomainModels.swift`
- `ShiftAssignment` — `DLCGasolineras/Models/DomainModels.swift`
- `EquipmentCategory` — `DLCGasolineras/Models/DomainModels.swift`
- `EquipmentStatus` — `DLCGasolineras/Models/DomainModels.swift`
- `StationEquipment` — `DLCGasolineras/Models/DomainModels.swift`
- `MaintenancePriority` — `DLCGasolineras/Models/DomainModels.swift`
- `MaintenanceStatus` — `DLCGasolineras/Models/DomainModels.swift`
- `MaintenanceOrder` — `DLCGasolineras/Models/DomainModels.swift`
- `HistoryRange` — `DLCGasolineras/Models/DomainModels.swift`

## Contratos API disponibles por área

### approvals (1 operaciones)
- `POST /approvals/{approvalId}/decision — decideApproval`
### auth (7 operaciones)
- `POST /auth/login — login`
- `POST /auth/refresh — refreshSession`
- `GET /auth/me — currentUser`
- `POST /auth/logout — logout`
- `GET /auth/me/capabilities — currentCapabilities`
- `POST /auth/activate — activateAccount`
- `POST /auth/password-reset/complete — completePasswordReset`
### branches (8 operaciones)
- `PUT /branches/{branchId}/operating-profile — setOperatingProfile`
- `GET /branches/{branchId}/configuration — branchConfiguration`
- `GET /branches — listBranches`
- `POST /branches — createBranchDraft`
- `GET /branches/{branchId} — getBranch`
- `PATCH /branches/{branchId}/onboarding — saveBranchOnboardingStep`
- `GET /branches/{branchId}/readiness — getBranchReadiness`
- `POST /branches/{branchId}/activate — activateBranch`
### cash (9 operaciones)
- `GET /branches/{branchId}/cash/registers — sin operationId`
- `POST /branches/{branchId}/cash/registers — sin operationId`
- `POST /branches/{branchId}/cash/sessions — sin operationId`
- `GET /branches/{branchId}/cash/sessions/{sessionId} — sin operationId`
- `POST /branches/{branchId}/cash/sessions/{sessionId}/movements — sin operationId`
- `GET /branches/{branchId}/cash/sessions/{sessionId}/movements — listCashMovements`
- `POST /branches/{branchId}/cash/sessions/{sessionId}/close — sin operationId`
- `GET /branches/{branchId}/cash/reviews — listCashReviews`
- `GET /branches/{branchId}/cash/sessions/{sessionId}/review — getCashReview`
### catalog (7 operaciones)
- `GET /fuel-products — listFuelProducts`
- `POST /fuel-products — createFuelProduct`
- `POST /fuel-products/{productId}/specifications — addFuelSpecification`
- `PUT /branches/{branchId}/fuel-offers/{fuelProductId} — enableBranchFuel`
- `PATCH /branches/{branchId}/fuel-offers/{fuelProductId} — updateFuelOffer`
- `GET /fuel-products/{productId} — fuelProductDetail`
- `PATCH /fuel-products/{productId} — updateFuelProduct`
### credit (9 operaciones)
- `POST /branches/{branchId}/finance/credit/customers — createCommercialCustomer`
- `GET /branches/{branchId}/finance/credit/customers — listCommercialCustomers`
- `POST /branches/{branchId}/finance/credit/customers/{customerId}/events — changeCommercialCustomer`
- `POST /branches/{branchId}/finance/credit/customers/{customerId}/buyers — addCommercialBuyer`
- `GET /branches/{branchId}/finance/credit/customers/{customerId}/statement — getCommercialAccountStatement`
- `POST /branches/{branchId}/finance/credit/sales/{saleId}/charge — chargeCommercialSale`
- `POST /branches/{branchId}/finance/credit/charges/{chargeId}/receipts — recordCommercialReceipt`
- `POST /branches/{branchId}/finance/credit/receipts/{receiptId}/verify — verifyCommercialBankReceipt`
- `POST /branches/{branchId}/finance/credit/customers/{customerId}/buyers/{buyerId}/access — changeCommercialBuyerAccess`
### cuts (14 operaciones)
- `GET /branches/{branchId}/cuts — listDailyCuts`
- `POST /branches/{branchId}/cuts/profiles — createCutProfile`
- `POST /branches/{branchId}/cuts/generate — generateDailyCuts`
- `POST /branches/{branchId}/cuts/{cutId}/open — openOperationalCut`
- `GET /branches/{branchId}/cuts/{cutId}/assets — getCutAssets`
- `POST /branches/{branchId}/cuts/{cutId}/meters — captureCutMeter`
- `GET /branches/{branchId}/cuts/{cutId}/progress — getCutProgress`
- `POST /branches/{branchId}/cuts/{cutId}/tanks — measureCutTank`
- `POST /branches/{branchId}/cuts/policies — createCutReconciliationPolicy`
- `POST /branches/{branchId}/cuts/{cutId}/prepare — prepareOperationalCut`
- `GET /branches/{branchId}/cuts/{cutId}/reconciliation — getCutReconciliation`
- `POST /branches/{branchId}/cuts/{cutId}/review — reviewOperationalCut`
- `POST /branches/{branchId}/cuts/{cutId}/close — closeOperationalCut`
- `GET /branches/{branchId}/cuts/{cutId}/closure — getClosedCutSnapshot`
### dispensing (12 operaciones)
- `POST /branches/{branchId}/nozzles/{nozzleId}/dispense-authorizations — authorizeNozzleDispense`
- `GET /branches/{branchId}/dispense-authorizations/{authorizationId} — getDispenseAuthorization`
- `POST /branches/{branchId}/dispense-authorizations/{authorizationId}/start — startDispenseAuthorization`
- `POST /branches/{branchId}/dispense-authorizations/{authorizationId}/progress — progressDispenseAuthorization`
- `POST /branches/{branchId}/dispense-authorizations/{authorizationId}/complete — completeDispenseAuthorization`
- `POST /branches/{branchId}/dispense-authorizations/{authorizationId}/cancel — cancelDispenseAuthorization`
- `POST /branches/{branchId}/dispense-authorizations/{authorizationId}/reconcile-no-flow — reconcileDispenseNoFlow`
- `POST /branches/{branchId}/dispense-authorizations/{authorizationId}/unknown — unknownDispenseAuthorization`
- `POST /branches/{branchId}/dispense-authorizations/{authorizationId}/device-start — deviceStart`
- `POST /branches/{branchId}/dispense-authorizations/{authorizationId}/device-query — deviceQuery`
- `GET /branches/{branchId}/dispense-authorizations/{authorizationId}/device-operations — deviceOperations`
- `GET /dispense-device/capabilities — deviceCapabilities`
### finance (8 operaciones)
- `POST /branches/{branchId}/finance/expense-categories — createExpenseCategory`
- `GET /branches/{branchId}/finance/expense-categories — listExpenseCategories`
- `POST /branches/{branchId}/finance/expenses — createExpense`
- `GET /branches/{branchId}/finance/expenses — listExpenses`
- `GET /branches/{branchId}/finance/expenses/{expenseId} — getExpense`
- `POST /branches/{branchId}/finance/expenses/{expenseId}/decision — decideExpense`
- `POST /branches/{branchId}/finance/expenses/{expenseId}/disbursements — disburseExpense`
- `GET /branches/{branchId}/finance/operating-results — getOperatingResults`
### health (2 operaciones)
- `GET /health/live — healthLive`
- `GET /health/ready — healthReady`
### imports (2 operaciones)
- `POST /imports/preview — createLegacyPreview`
- `GET /imports/{batchId} — getLegacyPreview`
### incidents (10 operaciones)
- `POST /branches/{branchId}/incidents — reportIncident`
- `GET /branches/{branchId}/incidents — listIncidents`
- `GET /branches/{branchId}/incidents/{incidentId} — getIncident`
- `POST /branches/{branchId}/incidents/{incidentId}/transition — advanceIncident`
- `POST /branches/{branchId}/incidents/{incidentId}/assessments — assessIncidentImpact`
- `POST /branches/{branchId}/incidents/{incidentId}/assessments/{assessmentId}/approve-loss — approveAndPostIncidentLoss`
- `POST /branches/{branchId}/incidents/{incidentId}/recovery-claims — createRecoveryClaim`
- `POST /branches/{branchId}/incidents/{incidentId}/recovery-claims/{claimId}/receipts — receiveRecovery`
- `GET /branches/{branchId}/anomalies — listAnomalyAlerts`
- `POST /branches/{branchId}/anomalies/{alertId}/review — reviewAnomalyAlert`
### infrastructure (18 operaciones)
- `POST /branches/{branchId}/tanks — createTank`
- `GET /branches/{branchId}/tanks — listTanks`
- `GET /branches/{branchId}/dispensers — listDispensers`
- `POST /branches/{branchId}/dispensers — createDispenser`
- `GET /branches/{branchId}/dispensers/{dispenserId} — dispenserDetail`
- `POST /branches/{branchId}/dispensers/{dispenserId}/nozzles — createNozzle`
- `PUT /branches/{branchId}/nozzles/{nozzleId}/tank-connection — connectNozzleTank`
- `GET /branches/{branchId}/nozzles/{nozzleId}/availability — nozzleAvailability`
- `POST /branches/{branchId}/asset-blocks — blockAsset`
- `GET /branches/{branchId}/asset-blocks — listAssetBlocks`
- `POST /branches/{branchId}/asset-blocks/{blockId}/resolve — resolveAssetBlock`
- `GET /branches/{branchId}/tanks/{tankId} — tankDetail`
- `PATCH /branches/{branchId}/{assetType}/{assetId}/status — changeAssetStatus`
- `GET /branches/{branchId}/nozzles/{nozzleId}/meter-readings — listNozzleMeterReadings`
- `POST /branches/{branchId}/nozzles/{nozzleId}/meter-readings — captureNozzleMeterReading`
- `POST /branches/{branchId}/nozzles/{nozzleId}/meter-readings/baseline — captureNozzleMeterBaseline`
- `POST /branches/{branchId}/nozzles/{nozzleId}/meter-changes — recordNozzleMeterChange`
- `GET /branches/{branchId}/dispense-authorizations — listDispenseAuthorizations`
### inventory (7 operaciones)
- `GET /branches/{branchId}/tanks/{tankId}/inventory — getTankInventoryBalance`
- `GET /branches/{branchId}/tanks/{tankId}/inventory/movements — listTankInventoryMovements`
- `POST /branches/{branchId}/tanks/{tankId}/inventory/opening — openTankInventory`
- `POST /branches/{branchId}/tanks/{tankId}/inventory/receipts — receiveTankInventory`
- `POST /branches/{branchId}/tanks/{tankId}/inventory/sales — recordFuelSale`
- `POST /branches/{branchId}/tanks/{tankId}/inventory/losses — recordFuelLoss`
- `POST /branches/{branchId}/tanks/{tankId}/inventory/adjustments — adjustTankInventory`
### maintenance (14 operaciones)
- `POST /branches/{branchId}/maintenance/assets — registerMaintenanceAsset`
- `GET /branches/{branchId}/maintenance/assets — listMaintenanceAssets`
- `POST /branches/{branchId}/maintenance/plans — createMaintenancePlan`
- `POST /branches/{branchId}/maintenance/orders — createMaintenanceOrder`
- `GET /branches/{branchId}/maintenance/orders — listMaintenanceOrders`
- `GET /branches/{branchId}/maintenance/orders/{orderId} — getMaintenanceOrder`
- `POST /branches/{branchId}/maintenance/orders/{orderId}/tasks — recordMaintenanceTask`
- `POST /branches/{branchId}/maintenance/orders/{orderId}/transition — advanceMaintenanceOrder`
- `POST /branches/{branchId}/maintenance/orders/{orderId}/release — releaseMaintenanceBlock`
- `POST /branches/{branchId}/maintenance/observations — recordEquipmentObservation`
- `POST /branches/{branchId}/maintenance/plans/generate — generateMaintenanceOrders`
- `POST /branches/{branchId}/maintenance/assets/{assetId}/intervals — transitionAssetAvailability`
- `GET /branches/{branchId}/maintenance/assets/{assetId}/availability — getAssetAvailability`
- `POST /branches/{branchId}/maintenance/orders/{orderId}/parts/use — sin operationId`
### metrics (4 operaciones)
- `GET /metrics/branches/{branchId}/dashboard — branchDashboard`
- `GET /metrics/http — httpMetricsPrometheus`
- `GET /metrics/network/dashboard — networkDashboard`
- `PATCH /metrics/branches/{branchId}/inventory-alert-policy — updateInventoryAlertPolicy`
### payments (14 operaciones)
- `POST /branches/{branchId}/dispense-authorizations/{authorizationId}/prepayments — collectPrepayment`
- `POST /branches/{branchId}/prepayments/{advanceId}/refund-requests — requestAdvanceRefund`
- `POST /branches/{branchId}/prepayments/{advanceId}/refunds — refundAdvance`
- `POST /branches/{branchId}/prepayments/{advanceId}/release-requests — requestPrepaymentRelease`
- `POST /branches/{branchId}/prepayments/{advanceId}/release-confirmations — confirmPrepaymentRelease`
- `POST /branches/{branchId}/prepayments/{advanceId}/allocate — allocatePrepayment`
- `POST /branches/{branchId}/prepayments/{advanceId}/resolve — resolvePrepayment`
- `POST /branches/{branchId}/payments — sin operationId`
- `POST /branches/{branchId}/payments/{attemptId}/resolve — sin operationId`
- `POST /branches/{branchId}/payment-events/{paymentEventId}/refund-requests — sin operationId`
- `POST /branches/{branchId}/payment-events/{paymentEventId}/refunds — sin operationId`
- `GET /branches/{branchId}/sales/{saleId}/payments — sin operationId`
- `GET /branches/{branchId}/sales/{saleId}/refund-requests — sin operationId`
- `GET /branches/{branchId}/prepayments — listPrepayments`
### pricing (9 operaciones)
- `GET /fuel-market-references — listFuelMarketReferences`
- `POST /fuel-market-references — createFuelMarketReference`
- `GET /branches/{branchId}/fuel-prices — getBranchFuelPrices`
- `GET /branches/{branchId}/fuel-prices/{fuelProductId}/history — getFuelPriceHistory`
- `GET /branches/{branchId}/fuel-price-proposals — listFuelPriceProposals`
- `POST /branches/{branchId}/fuel-price-proposals — createFuelPriceProposal`
- `POST /fuel-price-proposals/{proposalId}/approve — approveFuelPriceProposal`
- `POST /fuel-price-proposals/{proposalId}/reject — rejectFuelPriceProposal`
- `POST /fuel-price-proposals/{proposalId}/schedule — scheduleFuelPriceProposal`
### procurement (14 operaciones)
- `GET /suppliers — listSuppliers`
- `POST /suppliers — createSupplier`
- `GET /branches/{branchId}/purchase-orders — listPurchaseOrders`
- `POST /branches/{branchId}/purchase-orders — createPurchaseOrder`
- `POST /branches/{branchId}/purchase-orders/{orderId}/submit — submitPurchaseOrder`
- `POST /branches/{branchId}/purchase-orders/{orderId}/approve — approvePurchaseOrder`
- `POST /branches/{branchId}/purchase-orders/{orderId}/reject — rejectPurchaseOrder`
- `POST /branches/{branchId}/purchase-orders/{orderId}/mark-ordered — markOrderedPurchaseOrder`
- `POST /branches/{branchId}/purchase-orders/{orderId}/cancel — cancelPurchaseOrder`
- `POST /branches/{branchId}/purchase-orders/{orderId}/receipts — receivePurchaseOrderDelivery`
- `GET /branches/{branchId}/purchase-orders/{orderId} — getPurchaseOrder`
- `GET /branches/{branchId}/purchase-orders/{orderId}/invoices — listSupplierInvoices`
- `POST /branches/{branchId}/purchase-orders/{orderId}/invoices — createSupplierInvoice`
- `POST /branches/{branchId}/supplier-invoices/{invoiceId}/payments — recordSupplierInvoicePayment`
### procurement-planning (9 operaciones)
- `GET /branches/{branchId}/procurement/planning/demand — getFuelDemand`
- `POST /branches/{branchId}/procurement/planning/supplier-quotes — publishSupplierQuote`
- `GET /branches/{branchId}/procurement/planning/supplier-quotes — listSupplierQuotes`
- `POST /branches/{branchId}/procurement/planning/compare — comparePurchaseScenario`
- `POST /branches/{branchId}/procurement/planning/scenarios — savePurchaseScenario`
- `GET /branches/{branchId}/procurement/planning/scenarios — listPurchaseScenarios`
- `GET /branches/{branchId}/procurement/planning/scenarios/{scenarioId} — getPurchaseScenario`
- `POST /branches/{branchId}/procurement/planning/scenarios/{scenarioId}/decision — decidePurchaseScenario`
- `POST /branches/{branchId}/procurement/planning/scenarios/{scenarioId}/purchase-order — convertPurchaseScenario`
### reports (13 operaciones)
- `POST /branches/{branchId}/reports/runs — createReportRun`
- `GET /branches/{branchId}/reports/runs — listReportRuns`
- `GET /branches/{branchId}/reports/runs/{runId} — reportRunPage`
- `GET /branches/{branchId}/reports/runs/{runId}/export.csv — exportReportRunCsv`
- `GET /branches/{branchId}/reports/saved-filters — savedReportFilters`
- `POST /branches/{branchId}/reports/saved-filters — saveReportFilter`
- `DELETE /branches/{branchId}/reports/saved-filters/{filterId} — deleteSavedReportFilter`
- `GET /branches/{branchId}/reports/runs/{runId}/export.xlsx — exportReportXLSX`
- `GET /branches/{branchId}/reports/runs/{runId}/export.pdf — exportReportPDF`
- `POST /branches/{branchId}/reports/runs/{runId}/exports — requestReportExport`
- `GET /branches/{branchId}/reports/exports/{exportId} — reportExportStatus`
- `GET /branches/{branchId}/reports/exports/{exportId}/download — downloadReportExport`
- `POST /branches/{branchId}/reports/exports/{exportId}/cancel — cancelReportExport`
### sales (32 operaciones)
- `POST /branches/{branchId}/sales/from-dispatch — sin operationId`
- `GET /branches/{branchId}/sales/{saleId} — sin operationId`
- `GET /branches/{branchId}/dispense-authorizations/{authorizationId}/sale — sin operationId`
- `GET /branches/{branchId}/sales — sin operationId`
- `GET /branches/{branchId}/fuel-tax-policies — sin operationId`
- `POST /branches/{branchId}/fuel-tax-policies/proposals — sin operationId`
- `POST /branches/{branchId}/fuel-tax-policies/proposals/{proposalId}/approve — sin operationId`
- `POST /branches/{branchId}/fuel-tax-policies/preview — sin operationId`
- `GET /branches/{branchId}/pos/catalog — sin operationId`
- `POST /branches/{branchId}/pos/catalog/offers — sin operationId`
- `POST /branches/{branchId}/pos/stock/receipts — sin operationId`
- `GET /branches/{branchId}/pos/catalog/{productId}/lots — sin operationId`
- `POST /branches/{branchId}/sales/pos — sin operationId`
- `GET /branches/{branchId}/pos/catalog/{productId} — sin operationId`
- `POST /branches/{branchId}/pos/stock/lots/{lotId}/condition — sin operationId`
- `POST /branches/{branchId}/pos/transfers — sin operationId`
- `GET /branches/{branchId}/pos/transfers — sin operationId`
- `GET /branches/{branchId}/pos/transfers/{transferId} — sin operationId`
- `POST /branches/{branchId}/pos/transfers/{transferId}/receipts — sin operationId`
- `POST /branches/{branchId}/pos/transfers/{transferId}/close — sin operationId`
- `POST /branches/{branchId}/pos/stock/counts — sin operationId`
- `GET /branches/{branchId}/pos/stock/counts — sin operationId`
- `POST /branches/{branchId}/pos/stock/counts/{countId}/approve — sin operationId`
- `POST /branches/{branchId}/pos/returns — sin operationId`
- `GET /branches/{branchId}/pos/returns — sin operationId`
- `PATCH /branches/{branchId}/pos/catalog/global/{catalogId} — sin operationId`
- `PATCH /branches/{branchId}/pos/catalog/{productId}/assortment — sin operationId`
- `GET /branches/{branchId}/pos/stock/alerts — sin operationId`
- `POST /branches/{branchId}/pos/stock/counts/{countId}/loss — sin operationId`
- `POST /branches/{branchId}/sales/combined-receipts — createCombinedInternalReceipt`
- `GET /branches/{branchId}/sales/combined-receipts/{receiptId} — getCombinedInternalReceipt`
- `GET /branches/{branchId}/sales/{saleId}/combined-receipt — getCombinedReceiptForSale`
### services (5 operaciones)
- `POST /branches/{branchId}/pos/services/{productId}/details — configureService`
- `POST /branches/{branchId}/pos/services/offers/{offerId}/materials — addServiceMaterial`
- `GET /branches/{branchId}/pos/services/offers/{offerId}/materials — getServiceRecipe`
- `POST /branches/{branchId}/pos/services/sale-lines/{saleLineId}/fulfill — fulfillService`
- `GET /branches/{branchId}/pos/services/sale-lines/{saleLineId}/fulfillment — getServiceFulfillment`
### staff (13 operaciones)
- `POST /branches/{branchId}/staff/employees — sin operationId`
- `GET /branches/{branchId}/staff/employees — sin operationId`
- `POST /branches/{branchId}/staff/employees/{employeeId}/transition — sin operationId`
- `POST /branches/{branchId}/staff/shifts — sin operationId`
- `GET /branches/{branchId}/staff/shifts — sin operationId`
- `POST /branches/{branchId}/staff/shifts/{shiftId}/cancel — sin operationId`
- `POST /branches/{branchId}/staff/shifts/{shiftId}/attendance — sin operationId`
- `POST /branches/{branchId}/staff/shifts/{shiftId}/handovers — sin operationId`
- `POST /branches/{branchId}/staff/handovers/{handoverId}/acknowledge — sin operationId`
- `POST /branches/{branchId}/staff/dispensers/{dispenserId}/availability — sin operationId`
- `GET /branches/{branchId}/staff/employee-plans — sin operationId`
- `POST /branches/{branchId}/staff/employee-plans/{planId}/apply — sin operationId`
- `PATCH /branches/{branchId}/staff/employees/{employeeId} — updateEmployeeProfile`
### users (5 operaciones)
- `POST /users/invitations — inviteUser`
- `POST /users/{userId}/password-reset — issuePasswordReset`
- `POST /users/{userId}/status — changeUserStatus`
- `POST /users/{userId}/assignments — reassignUserRole`
- `GET /users — listUsers`

## Recorrido F01

1. `POST /auth/login` entrega TokenPair sin `data` envelope.
2. Guardar tokens en almacenamiento seguro móvil. `GET /auth/me` y `/auth/me/capabilities` usan `data`.
3. Gerente general obtiene sucursales con `GET /branches?status=active&limit=50`; sucursal propia se resuelve desde roles/asignaciones autorizadas, nunca desde un selector de rol.
4. `GET /metrics/branches/{branchId}/dashboard` y `GET /branches/{branchId}/dispensers`; detalle usa `GET /branches/{branchId}/dispensers/{dispenserId}`.
5. Incidencia de bomba: `POST /branches/{branchId}/incidents` con UUID `commandId`, `category=equipment_damage`, `severity`, `assetType=dispenser`, `assetId`, `description` de 12–2000 caracteres e ISO date-time. Reintentos reutilizan el mismo commandId.

## Discrepancia de contrato corregida

`RemoteIdentity` de Swift exige `organizationId`; `AuthService.me()` no lo seleccionaba. Se añadió a la respuesta y se tipó la respuesta 200 de OpenAPI para cubrir el DTO usado por ambas plataformas.
