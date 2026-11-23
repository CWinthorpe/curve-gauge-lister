// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {TestBase} from "../TestBase.sol";
import {CurveGaugeLister} from "../../contracts/CurveGaugeLister.sol";
import {VotiumAdapter} from "../../contracts/adapters/VotiumAdapter.sol";
import {VoteMarketAdapter} from "../../contracts/adapters/VoteMarketAdapter.sol";

/// @dev Extended local cheatcode surface for the fork suite (executor-owned;
/// no forge-std, no FFI). Declared against the same cheatcode dispatcher.
/// Only the subset the fork acceptance suite uses. `getBlockHash` is NOT
/// available on this Forge (probed: unknown selector 0xee82ac5e), so the
/// pinned block-hash comparison is enforced fail-closed by
/// scripts/test-fork.sh header preflight (plans/FORK-PLAN.md §2), while every
/// test asserts chain ID, forked block number and initial timestamp here.
interface FVm {
    struct Log {
        bytes32[] topics;
        bytes data;
        address emitter;
    }

    function createSelectFork(string calldata urlOrAlias, uint256 blockNumber) external returns (uint256);
    function envOr(string calldata name, string calldata defaultValue) external view returns (string memory value);
    function getBlockNumber() external view returns (uint256);
    function deal(address who, uint256 newBalance) external;
    function expectCall(address callee, bytes calldata data) external;
    function expectCall(address callee, uint256 value, bytes calldata data) external;
    function recordLogs() external;
    function getRecordedLogs() external view returns (Log[] memory logs);
    function prank(address newCaller) external;
    function startPrank(address newCaller) external;
    function stopPrank() external;
    function warp(uint256 newTimestamp) external;
    function chainId(uint256 newChainId) external;
}

/// @dev crvUSD (standard ERC20) probe surface. Cross-reference (S26):
/// `decimals`/`balanceOf` must agree with the product typed reads declared in
/// `contracts/interfaces/IERC20Minimal.sol`; `approve`/`transfer` mirror the
/// FIXTURE-only `IERC20Fixture` movement shape used for funding (production
/// movement is SafeToken low-level calls, so name/shape agreement with the
/// real token still matters here). `allowance` and `name`/`symbol` are
/// observation-only probes. Agreement here is a declaration cross-reference,
/// not a mechanical equivalence proof — the fork expectations below stay
/// independently checked.
interface IErc20Venue {
    function decimals() external view returns (uint8);
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function balanceOf(address) external view returns (uint256);
    function allowance(address, address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
}

/// @dev Real mainnet GaugeController surface (Vyper public getters).
/// Cross-reference (S26): `add_gauge(address,int128,uint256)`,
/// `gauge_types(address)` and `n_gauge_types()` are the product-declared
/// dependency subset — these MUST agree with
/// `contracts/interfaces/IListingController.sol`. `get_gauge_weight` is the
/// real controller's weight SURFACE, kept for observation/reference reads
/// only (S20); `admin`, `future_admin`, `n_gauges`, `gauges()`,
/// `commit_transfer_ownership`, `apply_transfer_ownership` and
/// `change_gauge_weight` are observation or fixture-authority roles, never
/// product call sites. A comment is not a mechanical equivalence proof —
/// the paid-addition witnesses below re-verify against the live venue.
interface IControllerVenue {
    function admin() external view returns (address);
    function future_admin() external view returns (address);
    function n_gauge_types() external view returns (int128);
    function n_gauges() external view returns (int128);
    function gauges(uint256) external view returns (address);
    function gauge_types(address) external view returns (int128);
    function get_gauge_weight(address) external view returns (uint256);
    function add_gauge(address, int128, uint256) external;
    function commit_transfer_ownership(address) external;
    function apply_transfer_ownership() external;
    function change_gauge_weight(address, uint256) external;
}

/// @dev Real MetaRegistry surface used by admission provenance.
/// Cross-reference (S26): the six reads here (is_registered, get_lp_token,
/// get_gauge, get_gauge_type, get_n_coins, get_coins) MUST agree with the
/// product-declared subset in `contracts/interfaces/ICurveRegistry.sol`.
/// `get_registry_handlers_from_pool` is observation-only (provenance
/// evidence, never an admission input).
interface IMetaRegistryVenue {
    function is_registered(address, uint256) external view returns (bool);
    function get_lp_token(address, uint256) external view returns (address);
    function get_gauge(address, uint256, uint256) external view returns (address);
    function get_gauge_type(address, uint256, uint256) external view returns (int128);
    function get_n_coins(address, uint256) external view returns (uint256);
    function get_coins(address, uint256) external view returns (address[8] memory);
    function get_registry_handlers_from_pool(address) external view returns (address[10] memory);
}

interface IGaugeVenue {
    function lp_token() external view returns (address);
    function is_killed() external view returns (bool);
    function factory() external view returns (address);
    function set_killed(bool) external;
}

interface IFactoryVenue {
    function admin() external view returns (address);
}

interface IProxyVenue {
    function dao() external view returns (address);
    function emergency_dao() external view returns (address);
    function set_killed(address) external;
}

interface IFdVenue {
    function token() external view returns (address);
    function is_killed() external view returns (bool);
    function admin() external view returns (address);
    function last_token_time() external view returns (uint256);
    function token_last_balance() external view returns (uint256);
    function tokens_per_week(uint256) external view returns (uint256);
    function can_checkpoint_token() external view returns (bool);
    function checkpoint_token() external;
}

/// @dev Deployed Votium.Incentive struct (viewIncentive returns it whole).
struct VenueIncentive {
    address token;
    uint256 amount;
    uint256 maxPerVote;
    uint256 distributed;
    uint256 recycled;
    address depositor;
    address[] excluded;
}

/// @dev Real Votium v2 venue surface. Cross-reference (S26): `activeRound()`
/// and `maxExclusions()` must agree with the product-declared subset in
/// `contracts/interfaces/IVotiumV2.sol`, and `depositUnevenSplitGauges`
/// reproduces the exact product call shape from that file. Everything else
/// (`requireAllowlist`, `tokenAllowed`, `platformFee`, `DENOMINATOR`,
/// `feeAddress`, `incentivesLength`, `inRoundGauges`, `gaugesLength`,
/// `roundGauges`, `virtualBalance`, `viewIncentive`) is observation-only
/// venue-state evidence independently asserted below — not product call
/// surface.
interface IVotiumVenue {
    function activeRound() external view returns (uint256);
    function requireAllowlist() external view returns (bool);
    function tokenAllowed(address) external view returns (bool);
    function platformFee() external view returns (uint256);
    function DENOMINATOR() external view returns (uint256);
    function feeAddress() external view returns (address);
    function maxExclusions() external view returns (uint256);
    function incentivesLength(uint256, address) external view returns (uint256);
    function inRoundGauges(uint256, address) external view returns (bool);
    function gaugesLength(uint256) external view returns (uint256);
    function roundGauges(uint256, uint256) external view returns (address);
    function virtualBalance(address) external view returns (uint256);
    function viewIncentive(uint256, address, uint256) external view returns (VenueIncentive memory);
    function depositUnevenSplitGauges(
        address _token,
        uint256 _round,
        address[] calldata _gauges,
        uint256[] calldata _amounts,
        uint256 _maxPerVote,
        address[] calldata _excluded
    ) external;
}

/// @dev Real CampaignRemoteManager surface (guards + immutables + events).
/// Cross-reference (S26): `CampaignParams` is the fork mirror of the
/// product-declared `ICampaignRemoteManager.CampaignCreationParams` — field
/// names, order and types (including `uint8 numberOfPeriods`) MUST agree,
/// and the campaign witnesses below observe the forwarded payload live;
/// `createCampaign`'s signature must agree with the product declaration.
/// `whitelistedPlatforms`, `LA_POSTE` and `TOKEN_FACTORY` are observation-
/// only venue-role reads. This annotation is a cross-reference; the fork's
/// independently checked expectations remain the actual evidence.
interface ICrmmVenue {
    error InvalidChainId();
    error PlatformNotWhitelisted();

    struct CampaignParams {
        uint256 chainId;
        address gauge;
        address manager;
        address rewardToken;
        uint8 numberOfPeriods;
        uint256 maxRewardPerVote;
        uint256 totalRewardAmount;
        address[] addresses;
        address hook;
        bool isWhitelist;
    }

    function whitelistedPlatforms(address) external view returns (bool);
    function LA_POSTE() external view returns (address);
    function TOKEN_FACTORY() external view returns (address);
    function createCampaign(CampaignParams memory, uint256, uint256, address) external payable;
}

interface ILaPosteVenue {
    function adapter() external view returns (address);
    function tokenFactory() external view returns (address);
    function sentNonces(uint256) external view returns (uint256);
}

interface ITokenFactoryVenue {
    function CHAIN_ID() external view returns (uint256);
    function minter() external view returns (address);
    function getTokenMetadata(address) external view returns (string memory, string memory, uint8);
}

interface ICcipAdapterVenue {
    function BASE_GAS_LIMIT() external view returns (uint256);
    function router() external view returns (address);
    function laPoste() external view returns (address);
    function getBridgeChainId(uint256) external view returns (uint256);
}

interface IRouterVenue {
    function isChainSupported(uint64) external view returns (bool);

    /// @dev Client.EVM2AnyMessage of the deployed CCIP router at this pin
    /// (selector 0x96f4e9f9 for ccipSend / 0x20487ded for getFee, verified
    /// against the deployed router ABI at block 26401019).
    struct CcipTokenAmount {
        address token;
        uint256 amount;
    }

    struct CcipEvm2AnyMessage {
        bytes receiver;
        bytes data;
        CcipTokenAmount[] tokenAmounts;
        address feeToken;
        bytes extraArgs;
    }

    function getOnRamp(uint64) external view returns (address);
    function getFee(uint64, CcipEvm2AnyMessage memory) external view returns (uint256);
    function ccipSend(uint64, CcipEvm2AnyMessage memory) external returns (bytes32);
}

/// @title ForkFixture
/// @notice Abstract fork fixture per plans/FORK-PLAN.md §1.1: fixed pins,
/// fork bring-up and header assertions, real funding, controller seating,
/// per-destination observation helpers. Contains no `test_*` methods and is
/// never instantiated by the default (offline) profile.
abstract contract ForkFixture is TestBase {
    /// @dev Extended cheatcode handle (same dispatcher as `vm`). NOTE: on
    /// this Forge build `expectCall(address,bytes)` is at-least-once with
    /// EXACT calldata matching (probed); exact multiplicity is proven by the
    /// log-count assertions instead.
    FVm internal constant fvm = FVm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    // ------------------------------------------------------------------
    // §2 fixed chain and transport pins
    // ------------------------------------------------------------------

    uint256 internal constant FORK_CHAIN_ID = 1;
    uint256 internal constant FORK_BLOCK = 26401019;
    bytes32 internal constant FORK_BLOCK_HASH = 0x55810b079923a14fb97ad548f5024f65530dbc4fb2357a38f41e13b3d27cb6d3;
    uint256 internal constant FORK_TIMESTAMP = 1794512471;
    string internal constant DEFAULT_RPC = "https://ethereum-rpc.publicnode.com";

    // ------------------------------------------------------------------
    // §3 constructor and real-state pins
    // ------------------------------------------------------------------

    address internal constant CONTROLLER = 0x2F50D538606Fa9EDD2B11E2446BEb18C9D5846bB;
    address internal constant DAO = 0x40907540d8a6C65c637785e8f8B742ae6b0b9968;
    address internal constant CRVUSD = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E;
    address internal constant FEEDIST = 0xD16d5eC345Dd86Fb63C6a9C43c517210F1027914;
    address internal constant METAREGISTRY = 0xF98B45FA17DE75FB1aD0e7aFD971b0ca00e379fC;
    address internal constant NG_HANDLER = 0xe06EBA9ceA16cc71d4498CdBA7240BB20d475890;
    address internal constant VOTIUM = 0x63942E31E98f1833A234077f47880A66136a2D1e;
    address internal constant CRM = 0x53aD4Cd1F1e52DD02aa9FC4A8250A1b74F351CA2;
    address internal constant VM_DESTINATION = 0x8c2c5A295450DDFf4CB360cA73FCCC12243D14D9;
    uint256 internal constant VM_DEST_CHAIN_ID = 42161;
    address internal constant LA_POSTE = 0xF0000058000021003E4754dCA700C766DE7601C2;
    address internal constant TOKEN_FACTORY = 0x96006425Da428E45c282008b00004a00002B345e;
    address internal constant CCIP_ADAPTER = 0x0235dC852BC0F9C6f3699029dc0A448edFfD49d5;
    /// @dev Derived through the adapter's real `router()` getter at the pin
    /// (exec11 corrected pin; the emitted getter result and the actual
    /// getFee/ccipSend calls both resolve here).
    address internal constant CCIP_ROUTER = 0x80226fc0Ee2b096224EeAc085Bb9a8cba1146f7D;
    /// @dev CCIP EVMExtraArgsV1 tag (deployed GasBadger adapter's
    /// `Client._argsToBytes(EVMExtraArgsV1(gasLimit))` wire prefix).
    bytes4 internal constant CCIP_EXTRA_ARGS_TAG = 0x97a657c9;
    address internal constant CRVUSD_HOLDER = 0x0655977FEb2f289A4aB78af67BAB0d17aAb84367;
    uint256 internal constant HOLDER_PINNED_BALANCE = 16440647424276528096928814;

    /// @dev V1ALIGN trusted-gauge validator pin (plans/V1ALIGN-PLAN.md §2.1;
    /// plans/V1ALIGN-WITNESSES.md §2): GaugeValidator runtime at the frozen
    /// pin (block 26401019) is 3,402 bytes with Keccak-256
    /// 0x2d684822a3f2bf6f99f902474289219041443a9d9cc94cbc28505050185016cd,
    /// including metadata. Re-asserted read-only before every core
    /// construction; a mismatch is a suite failure, never a skip or a
    /// substitute dependency. (Moved out of the retired bounty fork fixture;
    /// it now belongs to the no-bounty V1 kit independently of bounty deps.)
    address internal constant TRUSTED_VALIDATOR = 0x888888c34a46d0b2A34e9204e5273208E670e784;
    uint256 internal constant TRUSTED_VALIDATOR_SIZE = 3402;
    bytes32 internal constant H_TRUSTED_VALIDATOR = 0x2d684822a3f2bf6f99f902474289219041443a9d9cc94cbc28505050185016cd;

    address internal constant FACTORY = 0x6A8cbed756804B16E05E741eDaBd5cB544AE21bf;
    address internal constant AMM_PROXY = 0xeDA0108D5bB8cdE2ba4A59E22F3Ed5d211C77187;
    address internal constant EMERGENCY_DAO = 0x467947EE34aF926cF1DCac093870f613C96B1E0c;
    address internal constant VOTIUM_FEE_ADDRESS = 0x29e3b0E8dF4Ee3f71a62C34847c34E139fC0b297;

    // ------------------------------------------------------------------
    // §4 fixed candidate table (primary; the fallback candidates were
    // retired with the lean audit's cut pins test — one primary pinned
    // provenance path remains, re-run inside every fixture)
    // ------------------------------------------------------------------

    address internal constant POOL_PRIMARY = 0x09CA19cF9F035112A54F3f1FAbB622c2578342C9;
    address internal constant GAUGE_PRIMARY = 0x9f96B45A2ea3Fea791513aa3A7921d474105B23e;
    address internal constant COIN_P0 = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant COIN_P1 = 0x5377680B5986296AA4F9e684e5315a4F24832e56;

    uint256 internal constant HANDLER_ID = 0;
    uint256 internal constant GAUGE_INDEX = 0;
    int128 internal constant DERIVED_TYPE = 0;
    uint256 internal constant N_GAUGES_PINNED = 1052;

    // ------------------------------------------------------------------
    // §6.1 real settlement oracles / schedule pins
    // ------------------------------------------------------------------

    uint256 internal constant FEE = 10_000e18;
    uint256 internal constant QUARTER = 2_500e18;
    uint256 internal constant EPOCHS = 4;
    uint256 internal constant WEEK = 604800;
    uint256 internal constant LISTING_EPOCH = 1794441600;

    /// @dev The four exact maturity timestamps (fixed maturity mapping at
    /// this pin: 136/137/137/138; checked live against activeRound()).
    function _maturity(uint256 k) internal pure returns (uint256) {
        if (k == 0) return 1795046400;
        if (k == 1) return 1795651200;
        if (k == 2) return 1796256000;
        return 1796860800;
    }

    function _maturityRound(uint256 k) internal pure returns (uint256) {
        if (k == 0) return 136;
        if (k == 1) return 137;
        if (k == 2) return 137;
        return 138;
    }
    uint256 internal constant ACTIVE_ROUND_AT_FORK = 136;
    uint256 internal constant VOTIUM_PLATFORM_FEE = 200;
    uint256 internal constant VOTIUM_DENOMINATOR = 10000;

    uint256 internal constant CAMPAIGN_CREATION_GAS = 2_000_000;
    uint256 internal constant BLACKLISTED_ADDRESS_GAS = 50_000;
    uint256 internal constant ADAPTER_GAS_PRICE = 1 gwei;
    uint256 internal constant CALL_VALUE = CAMPAIGN_CREATION_GAS * ADAPTER_GAS_PRICE; // 2e15 wei
    uint256 internal constant CCIP_BASE_GAS_LIMIT = 50_000;
    uint256 internal constant FIXTURE_ETH_FLOAT = 0.01 ether;

    // ------------------------------------------------------------------
    // Event topic0 constants (pinned signatures)
    // ------------------------------------------------------------------

    bytes32 internal constant T_NEW_GAUGE = keccak256("NewGauge(address,int128,uint256)");
    bytes32 internal constant T_MESSAGE_SENT = keccak256(
        "MessageSent(uint256,uint256,address,address,(uint256,address,address,(address,uint256)[],(string,string,uint8)[],bytes,uint256))"
    );
    bytes32 internal constant T_CAMPAIGN_PAYLOAD_SENT = keccak256(
        "CampaignCreationPayloadSent((uint256,address,address,address,uint8,uint256,uint256,address[],address,bool))"
    );
    bytes32 internal constant T_NEW_INCENTIVE =
        keccak256("NewIncentive(uint256,address,uint256,uint256,address,uint256,address[],address,bool)");
    bytes32 internal constant T_TRANSFER = keccak256("Transfer(address,address,uint256)");
    bytes32 internal constant T_APPROVAL = keccak256("Approval(address,address,uint256)");
    bytes32 internal constant T_GAUGE_LISTED =
        keccak256("GaugeListed(address,address,address,int128,uint256,uint256,bool)");
    bytes32 internal constant T_QUARTER_RELEASED = keccak256("QuarterReleased(address,uint256,uint256,uint256)");
    bytes32 internal constant T_PLATFORM_DEPOSIT =
        keccak256("PlatformDeposit(address,address,uint256,uint256,uint256,bytes32)");
    bytes32 internal constant T_ESCROW_CONFISCATED = keccak256("EscrowConfiscated(address,address,uint256,uint256)");
    bytes32 internal constant T_FEE_CHECKPOINT_RESULT = keccak256("FeeCheckpointResult(bool)");
    bytes32 internal constant T_VOTIUM_DEPOSIT = keccak256("VotiumDeposit(address,uint256,uint256,uint256,bytes32)");
    bytes32 internal constant T_CAMPAIGN_DEPOSIT =
        keccak256("CampaignDeposit(address,uint256,uint256,uint256,bytes32)");

    // ------------------------------------------------------------------
    // Dependency code hashes pinned from block 26401019 (eth_getCode +
    // keccak256; recorded in review/FORK-EXECUTION.md)
    // ------------------------------------------------------------------

    bytes32 internal constant H_CONTROLLER = 0x655bec9519bc4e87c56bb2c54767c5ae6407f8be1b29140f5110c29d9607d42d;
    bytes32 internal constant H_CRVUSD = 0x7d33300cc75c4738e04e1f8c838b8b4fbb1c40d046131088463f70f9c712325f;
    bytes32 internal constant H_FD = 0x04ba5a2515caeeb9a3839afb59c8a0cc1f76df17b7f436171782fe880be1ad8d;
    bytes32 internal constant H_META = 0x6110f2aba179ac22c384acd7e02165ee753655d5b07aa096a63332257a27c413;
    bytes32 internal constant H_VOTIUM = 0x80ef19adc09a7376cdab165f630d75bff769e1403252542eb91e0161c473c558;
    bytes32 internal constant H_CRM = 0xe7d8bbfc0ecdc5c82bb57081672b1ddd7cecff00eac5313affd3197bcd79d546;
    bytes32 internal constant H_GAUGE_PRIMARY = 0x87bbcf1597c85d936ef442b3794daedb4784df0b0777d236307aef0fbd45a5bf;
    bytes32 internal constant H_POOL_PRIMARY = 0xe179d12f224702451639b296511f523224d92d5a84d2596c9decaa26af63db7f;

    // ------------------------------------------------------------------
    // Console evidence events (printed by forge at -vvv)
    // ------------------------------------------------------------------

    event log_named_address(string key, address val);
    event log_named_uint(string key, uint256 val);
    event log_named_bool(string key, bool val);

    // ------------------------------------------------------------------
    // Additional comparisons (TestBase cannot be edited and same-name
    // overloads across inheritance are disallowed, so these are distinct).
    // ------------------------------------------------------------------

    function _assertBytesEq(bytes memory a, bytes memory b, string memory label) internal pure {
        require(keccak256(a) == keccak256(b), label);
    }

    function _assertStringEq(string memory a, string memory b, string memory label) internal pure {
        require(keccak256(bytes(a)) == keccak256(bytes(b)), label);
    }

    function _assertI128Eq(int128 a, int128 b, string memory label) internal pure {
        require(a == b, label);
    }

    // ------------------------------------------------------------------
    // Shared fixtures
    // ------------------------------------------------------------------

    struct Trio {
        CurveGaugeLister lister;
        VotiumAdapter va;
        VoteMarketAdapter vma;
    }

    /// @dev Full pre/post-observation state of every money destination plus
    /// a hash of the complete public Listing record (plans/FORK-PLAN.md §6):
    /// scalar custody/accounting counters that the surviving tests directly
    /// use, with the whole record bound by one keccak equality. Receipt counts
    /// remain in the snapshot; nested per-record receipt copies do not (a
    /// reverted transaction rolls back its state changes). auditfix001 §7:
    /// FD accounting fields (cursor/accounted balance/buckets) stay LOCAL to
    /// the affected tests rather than broadening this snapshot.
    struct Snap {
        uint256 payerCrv;
        uint256 listerCrv;
        uint256 vaCrv;
        uint256 vmaCrv;
        uint256 crmCrv;
        uint256 tfCrv;
        uint256 fdCrv;
        uint256 votiumCrv;
        uint256 feeCrv;
        uint256 vmaEth;
        uint256 lpNonce;
        uint256 vmaDeposits;
        uint256 len136;
        uint256 len137;
        uint256 len138;
        uint256 virtualCrv;
        uint256 totalEscrow;
        uint256 nGauges;
        bytes32 listingHash;
    }

    /// @dev Resolve the RPC endpoint exactly like the script: environment
    /// override for the endpoint only, never for the block.
    function _rpc() internal view returns (string memory) {
        return fvm.envOr("MAINNET_RPC_URL", DEFAULT_RPC);
    }

    /// @dev keeper checkpointFees without privileged scope.
    function _keeperCheckpointFees(Trio memory t) internal returns (bool) {
        fvm.prank(keeper());
        return t.lister.checkpointFees();
    }

    /// @dev Settlement invoked by the unrelated keeper, without privileged
    /// prank scope beyond the caller identity (§5.1).
    function _keeperCheckpoint(Trio memory t, address gauge) internal returns (uint256, uint256) {
        fvm.prank(keeper());
        return t.lister.checkpoint(gauge);
    }

    function _keeperConfiscate(Trio memory t, address gauge) internal returns (uint256) {
        fvm.prank(keeper());
        return t.lister.confiscate(gauge);
    }

    // ------------------------------------------------------------------
    // Revert-probe helpers (try/catch so the test CONTINUES after the
    // expected revert and can assert complete state restoration; a plain
    // expectRevert would end the test frame at the reverting call).
    // CX-FORK-SETUP: the never-referenced `_probeFreeListRevert`,
    // `_probeGaugeKillRevert` and `_probeProxyKillRevert` helpers were
    // pruned after confirming no scenario calls them; every retained probe
    // checks material arguments/revert data (exact `want` bytes).
    // ------------------------------------------------------------------

    function _probeListGaugeRevert(Trio memory t, bytes memory want, string memory label) internal {
        fvm.prank(payer());
        try t.lister.listGauge(POOL_PRIMARY, GAUGE_PRIMARY, GAUGE_INDEX, HANDLER_ID) {
            assertTrue(false, string.concat(label, " (expected revert, call succeeded)"));
        } catch (bytes memory rd) {
            _assertBytesEq(rd, want, label);
        }
    }

    function _probeControllerCommitRevert(address from, bytes memory want, string memory label) internal {
        fvm.prank(from);
        try IControllerVenue(CONTROLLER).commit_transfer_ownership(rando()) {
            assertTrue(false, string.concat(label, " (expected revert, call succeeded)"));
        } catch (bytes memory rd) {
            _assertBytesEq(rd, want, label);
        }
    }

    function _probeControllerApplyRevert(address from, bytes memory want, string memory label) internal {
        fvm.prank(from);
        try IControllerVenue(CONTROLLER).apply_transfer_ownership() {
            assertTrue(false, string.concat(label, " (expected revert, call succeeded)"));
        } catch (bytes memory rd) {
            _assertBytesEq(rd, want, label);
        }
    }

    function _probeCheckpointRevert(Trio memory t, address gauge, bytes memory want, string memory label) internal {
        fvm.prank(keeper());
        try t.lister.checkpoint(gauge) returns (uint256 a, uint256 b) {
            assertTrue(false, string.concat(label, " (expected revert, succeeded ", _u(a), "/", _u(b), ")"));
        } catch (bytes memory rd) {
            _assertBytesEq(rd, want, label);
        }
    }

    function _u(uint256 v) internal pure returns (string memory) {
        if (v == 0) return "0";
        uint256 n;
        uint256 x = v;
        while (x > 0) {
            x /= 10;
            n++;
        }
        bytes memory b = new bytes(n);
        for (uint256 i = 0; i < n; ++i) {
            b[n - 1 - i] = bytes1(uint8(48 + (v % 10)));
            v /= 10;
        }
        return string(b);
    }

    // ------------------------------------------------------------------
    // Fresh-fork + full-standard seed (fresh fork, real trio, seating,
    // funding, approval, paid primary listing). One call site per need.
    // ------------------------------------------------------------------

    function _freshSeed(uint16 votiumBps) internal returns (Trio memory t) {
        _freshFork();
        t = _seedStandard(votiumBps);
    }

    /// @dev Fresh fork at the pinned block + mandatory header assertions
    /// (CX-FORK-CLOCK): these are TWO SEPARATE checks and neither
    /// substitutes for the other.
    ///  (1) SELECTED FORK IDENTITY — the chain-id and block-number
    ///      assertions below verify the node served the pinned chain/block
    ///      this test builds on; the fail-closed ENDPOINT/HEADER selection
    ///      is the scripts/test-fork.sh preflight (it compares the returned
    ///      pinned block hash/number/timestamp over RPC and refuses to run
    ///      the suite on any mismatch — the fixture's in-EVM view cannot
    ///      replace that preflight because it only sees whatever the node
    ///      served).
    ///  (2) SCENARIO CLOCK RESTORATION — the optional warp and the
    ///      timestamp assertion re-anchor the ENVIRONMENT clock to the
    ///      pinned timestamp after an earlier subcase warped it (a
    ///      mid-test fresh fork inherits the process-level env clock).
    ///      Identity selection is not re-proved here; restoration does not
    ///      re-anchor state reads, which stay pinned to FORK_BLOCK.
    function _freshFork() internal {
        fvm.createSelectFork(_rpc(), FORK_BLOCK);
        // (2) Scenario clock restoration (env-only repair; every state read
        // stays pinned to FORK_BLOCK) so every test provably starts at the
        // plan's timestamp.
        if (block.timestamp != FORK_TIMESTAMP) {
            fvm.warp(FORK_TIMESTAMP);
        }
        // (1) Selected fork identity as served by the node (separate from
        // the shell preflight's header comparison above).
        assertEq(block.chainid, FORK_CHAIN_ID, "fork chain id");
        assertEq(block.number, FORK_BLOCK, "fork block number");
        assertEq(fvm.getBlockNumber(), FORK_BLOCK, "cheat fork block number");
        assertEq(block.timestamp, FORK_TIMESTAMP, "fork initial timestamp");
    }

    /// @dev Deterministic test actors, distinct from every pinned role.
    function payer() internal pure returns (address) {
        return actor("exec10-payer");
    }

    function keeper() internal pure returns (address) {
        return actor("exec10-keeper");
    }

    function donor() internal pure returns (address) {
        return actor("exec10-donor");
    }

    function rando() internal pure returns (address) {
        return actor("exec10-outsider");
    }

    function _assertActorsDistinct() internal pure {
        assertTrue(payer() != DAO && payer() != CONTROLLER && payer() != GAUGE_PRIMARY, "payer distinct");
        assertTrue(payer() != AMM_PROXY && payer() != EMERGENCY_DAO && payer() != FEEDIST, "payer distinct 2");
        assertTrue(keeper() != payer() && donor() != payer() && donor() != keeper(), "actors distinct");
        assertTrue(rando() != payer() && rando() != DAO && rando() != EMERGENCY_DAO, "outsider distinct");
    }

    /// @dev Read-only identity check of the constructor-pinned validator at
    /// the CURRENT fork block before any core construction: the live runtime
    /// must equal the recorded 3,402-byte GaugeValidator including metadata.
    /// A mismatch is a suite failure, never a skip or a substitute
    /// dependency.
    function _assertValidatorPinAtFork() internal view {
        bytes memory vcode = TRUSTED_VALIDATOR.code;
        assertEq(uint256(vcode.length), TRUSTED_VALIDATOR_SIZE, "fork: validator runtime size 3402");
        assertEq(keccak256(vcode), H_TRUSTED_VALIDATOR, "fork: validator runtime keccak");
    }

    /// @dev ONE destination-parameterized trio constructor/binding proof
    /// shared by both fork trio targets (CX-FORK-SETUP): primary via
    /// `_deployTrio` (VM_DESTINATION), alternate via `_deployTrioAltVm`.
    /// Preserved in full inside the shared body: §4/R8-4 read-only primary
    /// provenance + code/kill-authority checks BEFORE any seating, funding
    /// or listing write (auditfix001 §7); V1ALIGN validator-pin identity
    /// re-verified read-only before construction with the core wired to the
    /// ACTUAL pinned validator; the explicit S03 controller-pin assertion
    /// (now applied to BOTH targets); owner-gated one-time DAO-scoped
    /// bindings with getter readback; and the paused postcondition —
    /// activation stays a SEPARATE explicit step (`_activatePaidAdmission`),
    /// never folded into deploy.
    function _deployTrioAt(uint16 votiumBps, address vmDestination) internal returns (Trio memory t) {
        _assertPrimaryProvenance();
        t.va = new VotiumAdapter(CRVUSD, DAO, VOTIUM);
        t.vma = new VoteMarketAdapter(CRVUSD, DAO, CRM, vmDestination);
        _assertValidatorPinAtFork();
        t.lister = new CurveGaugeLister(
            DAO,
            CRVUSD,
            CONTROLLER,
            FEEDIST,
            CurveGaugeLister.AdmissionConfig(METAREGISTRY, 8),
            CurveGaugeLister.PlatformConfig(address(t.va), address(t.vma), votiumBps),
            TRUSTED_VALIDATOR
        );
        // S03: the witnessed production composition targets the pinned real
        // controller; the core's immutable must equal it exactly.
        assertEq(t.lister.controller(), CONTROLLER, "S03: composition target is the pinned GaugeController");
        fvm.startPrank(DAO);
        t.va.setLister(address(t.lister));
        t.vma.setLister(address(t.lister));
        fvm.stopPrank();
        assertEq(t.va.lister(), address(t.lister), "votium adapter bound to this core");
        assertEq(t.vma.lister(), address(t.lister), "votemarket adapter bound to this core");
        // S05: construction and binding complete PAUSED (runbook §Roles and
        // deployment step 4). Paid admission stays disabled until the
        // fixture calls `_activatePaidAdmission` after its own applicable
        // prerequisites — the final activation is explicit, never implicit
        // in the deploy step.
        assertTrue(t.lister.paused(), "trio stays paused after deploy/bind (activation is a separate step)");
    }

    /// @dev Standard trio: BOTH adapters on their primary real pins
    /// (VoteMarket adapter bound to the whitelisted destination).
    function _deployTrio(uint16 votiumBps) internal returns (Trio memory t) {
        return _deployTrioAt(votiumBps, VM_DESTINATION);
    }

    /// @dev Trio with a VoteMarket adapter bound to an alternate (proven
    /// non-whitelisted) destination; Votium side stays the real adapter.
    /// Same shared setup as `_deployTrio` (CX-FORK-SETUP): pre-write
    /// provenance first, both adapters bound under the narrowly scoped DAO
    /// prank, controller pin asserted, paused postcondition.
    function _deployTrioAltVm(uint16 votiumBps, address altDest) internal returns (Trio memory t) {
        return _deployTrioAt(votiumBps, altDest);
    }

    /// @dev S05: the explicit final activation step for positive rollout
    /// fixtures — the DAO owner unpauses ONLY after the applicable
    /// prerequisites have been arranged (bindings read back in
    /// `_deployTrio`, plus controller seating, funding and approval where
    /// the scenario needs them). Mirrors docs/OPERATIONS.md: paused setup,
    /// verified activation last. Not applicable to the DAO-free lane, which
    /// works while paused.
    function _activatePaidAdmission(Trio memory t) internal {
        fvm.prank(DAO);
        t.lister.setPaused(false);
        assertFalse(t.lister.paused(), "paid admission activated explicitly");
    }

    /// @dev §5.2 fork-only seating: real controller two-step admin transfer
    /// by the OLD admin (DAO). NOT production GaugeAdder seating.
    function _seat(CurveGaugeLister lister) internal {
        fvm.startPrank(DAO);
        IControllerVenue(CONTROLLER).commit_transfer_ownership(address(lister));
        IControllerVenue(CONTROLLER).apply_transfer_ownership();
        fvm.stopPrank();
        assertEq(IControllerVenue(CONTROLLER).admin(), address(lister), "controller admin seated");
    }

    /// @dev §5.1 fixture funding: impersonate the real crvUSD holder for one
    /// transfer of exactly FEE; assert exact debit and credit both sides.
    function _fundPayerOnce(address to) internal {
        uint256 holderBefore = IErc20Venue(CRVUSD).balanceOf(CRVUSD_HOLDER);
        uint256 toBefore = IErc20Venue(CRVUSD).balanceOf(to);
        fvm.prank(CRVUSD_HOLDER);
        IErc20Venue(CRVUSD).transfer(to, FEE);
        assertEq(IErc20Venue(CRVUSD).balanceOf(CRVUSD_HOLDER), holderBefore - FEE, "exact holder debit (10000e18)");
        assertEq(IErc20Venue(CRVUSD).balanceOf(to), toBefore + FEE, "exact payer credit");
    }

    function _fundPayer(address to, uint256 times) internal {
        for (uint256 i = 0; i < times; ++i) {
            _fundPayerOnce(to);
        }
    }

    /// @dev Payer approves exactly FEE to the lister.
    function _approveFee(Trio memory t) internal {
        fvm.prank(payer());
        IErc20Venue(CRVUSD).approve(address(t.lister), FEE);
        assertEq(IErc20Venue(CRVUSD).allowance(payer(), address(t.lister)), FEE, "fee approval");
    }

    /// @dev §5.1 ETH float via vm.deal to a fresh donor + a normal payable
    /// call into the VoteMarket adapter receive(); never to a real ingress.
    function _topUpVm(Trio memory t, uint256 weiAmount) internal {
        fvm.deal(donor(), FIXTURE_ETH_FLOAT * 2);
        uint256 beforeBal = address(t.vma).balance;
        fvm.prank(donor());
        (bool ok,) = payable(address(t.vma)).call{value: weiAmount}("");
        assertTrue(ok, "float top-up delivered");
        assertEq(address(t.vma).balance, beforeBal + weiAmount, "adapter float credited exactly");
    }

    /// @dev Full standard seed on the CURRENT fork: real trio (deploy/bind
    /// paused), seating, funding, approval — then the EXPLICIT final
    /// activation (S05) immediately before the paid listing of the primary
    /// candidate.
    function _seedStandard(uint16 votiumBps) internal returns (Trio memory t) {
        _assertActorsDistinct();
        t = _deployTrio(votiumBps);
        _seat(t.lister);
        _fundPayer(payer(), 1);
        _approveFee(t);
        _activatePaidAdmission(t);
        fvm.prank(payer());
        t.lister.listGauge(POOL_PRIMARY, GAUGE_PRIMARY, GAUGE_INDEX, HANDLER_ID);
    }

    // ------------------------------------------------------------------
    // Kill authority (real proxy wrapper / real gauge)
    // ------------------------------------------------------------------

    function _killViaProxy(address from, address gauge) internal {
        fvm.prank(from);
        IProxyVenue(AMM_PROXY).set_killed(gauge);
        assertTrue(IGaugeVenue(gauge).is_killed(), "gauge killed via real proxy");
    }

    /// @dev §5.3 terminal-after-unkill control: impersonate the verified
    /// DIRECT factory admin (the proxy address itself) for gauge.set_killed.
    function _unkillViaDirectAdmin(address gauge) internal {
        assertEq(IFactoryVenue(FACTORY).admin(), AMM_PROXY, "factory admin is the proxy");
        fvm.prank(AMM_PROXY);
        IGaugeVenue(gauge).set_killed(false);
        assertFalse(IGaugeVenue(gauge).is_killed(), "unkilled by direct factory admin");
    }

    // ------------------------------------------------------------------
    // Per-destination observation
    // ------------------------------------------------------------------

    function _snap(Trio memory t) internal view returns (Snap memory s) {
        s.payerCrv = IErc20Venue(CRVUSD).balanceOf(payer());
        s.listerCrv = IErc20Venue(CRVUSD).balanceOf(address(t.lister));
        s.vaCrv = IErc20Venue(CRVUSD).balanceOf(address(t.va));
        s.vmaCrv = IErc20Venue(CRVUSD).balanceOf(address(t.vma));
        s.crmCrv = IErc20Venue(CRVUSD).balanceOf(CRM);
        s.tfCrv = IErc20Venue(CRVUSD).balanceOf(TOKEN_FACTORY);
        s.fdCrv = IErc20Venue(CRVUSD).balanceOf(FEEDIST);
        s.votiumCrv = IErc20Venue(CRVUSD).balanceOf(VOTIUM);
        s.feeCrv = IErc20Venue(CRVUSD).balanceOf(IVotiumVenue(VOTIUM).feeAddress());
        s.vmaEth = address(t.vma).balance;
        s.lpNonce = ILaPosteVenue(LA_POSTE).sentNonces(VM_DEST_CHAIN_ID);
        s.vmaDeposits = t.vma.depositCount();
        s.len136 = IVotiumVenue(VOTIUM).incentivesLength(136, GAUGE_PRIMARY);
        s.len137 = IVotiumVenue(VOTIUM).incentivesLength(137, GAUGE_PRIMARY);
        s.len138 = IVotiumVenue(VOTIUM).incentivesLength(138, GAUGE_PRIMARY);
        s.virtualCrv = IVotiumVenue(VOTIUM).virtualBalance(CRVUSD);
        s.totalEscrow = t.lister.totalEscrow();
        s.nGauges = uint256(int256(IControllerVenue(CONTROLLER).n_gauges()));
        // The complete public Listing record, bound by one hash equality.
        s.listingHash = keccak256(abi.encode(t.lister.getListing(GAUGE_PRIMARY)));
    }

    /// @dev §5 flattened whole-state comparison: ONE hash equality over the
    /// complete value-only Snap — every custody/accounting counter plus the
    /// public Listing hash folded in by `_snap` — instead of a field-by-field
    /// ladder (LEAN-AUDIT2 item 5.1).
    function _assertSnapEq(Snap memory a, Snap memory b, string memory label) internal pure {
        assertEq(keccak256(abi.encode(a)), keccak256(abi.encode(b)), label);
    }

    // ------------------------------------------------------------------
    // Ledger assertions (single-listing fixture law, §6)
    // ------------------------------------------------------------------

    /// @dev Anchored post-step ledger (§6): the accounting identity AND the
    /// expected absolute values (deposited = FEE, remaining = FEE minus
    /// released quarters, no confiscation, Active/Exhausted status) plus
    /// totalEscrow. Immutable metadata is bound at initial admission (direct
    /// assertions in paid admission) and not reasserted here.
    function _assertLedger(Trio memory t, address gauge, uint8 released, bool exhausted) internal view {
        CurveGaugeLister lister = t.lister;
        CurveGaugeLister.Listing memory rec = lister.getListing(gauge);
        assertEq(rec.deposited, FEE, "deposited anchored to FEE");
        assertEq(rec.deposited, rec.remaining + rec.released + rec.confiscated, "deposited identity");
        assertEq(rec.released, QUARTER * uint256(released), "released identity");
        assertEq(uint256(rec.epochsReleased), uint256(released), "epochsReleased");
        assertEq(rec.remaining, exhausted ? 0 : FEE - QUARTER * uint256(released), "remaining anchored");
        assertEq(rec.confiscated, 0, "no confiscation on the release path");
        assertEq(uint256(rec.status), exhausted ? 2 : 1, exhausted ? "status Exhausted" : "status Active");
        assertEq(lister.totalEscrow(), rec.remaining, "totalEscrow == remaining");
    }

    /// @dev Anchored terminal Confiscated ledger (§6): the COMPLETE financial
    /// record — deposited anchored to FEE, the part-sum identity,
    /// released/epochsReleased/remaining/confiscated, status, totalEscrow —
    /// for a listing whose Active life released `releasedWei` across
    /// `releasedWei / QUARTER` quarters before the flag confiscation seized
    /// the rest. Immutable metadata is bound at initial admission.
    function _assertConfiscatedLedger(Trio memory t, address gauge, uint256 releasedWei, uint256 confiscatedWei)
        internal
        view
    {
        CurveGaugeLister lister = t.lister;
        CurveGaugeLister.Listing memory rec = lister.getListing(gauge);
        assertEq(rec.deposited, FEE, "confiscated ledger: deposited anchored to FEE");
        assertEq(
            rec.deposited, rec.remaining + rec.released + rec.confiscated, "confiscated ledger: deposited identity"
        );
        assertEq(rec.released, releasedWei, "confiscated ledger: released");
        assertEq(rec.released, QUARTER * uint256(rec.epochsReleased), "confiscated ledger: released identity");
        assertEq(uint256(rec.epochsReleased), releasedWei / QUARTER, "confiscated ledger: epochsReleased");
        assertEq(rec.remaining, 0, "confiscated ledger: remaining zero");
        assertEq(rec.confiscated, confiscatedWei, "confiscated ledger: confiscated");
        assertEq(uint256(rec.status), 3, "confiscated ledger: status Confiscated");
        assertEq(lister.totalEscrow(), rec.remaining, "confiscated ledger: totalEscrow == remaining");
    }

    function _assertAdaptersEmpty(Trio memory t) internal view {
        assertEq(IErc20Venue(CRVUSD).balanceOf(address(t.va)), 0, "votium adapter retains no crvUSD");
        assertEq(IErc20Venue(CRVUSD).balanceOf(address(t.vma)), 0, "votemarket adapter retains no crvUSD");
    }

    function _assertZeroApprovals(Trio memory t) internal view {
        assertEq(IErc20Venue(CRVUSD).allowance(address(t.lister), address(t.va)), 0, "lister->va allowance");
        assertEq(IErc20Venue(CRVUSD).allowance(address(t.lister), address(t.vma)), 0, "lister->vma allowance");
        assertEq(IErc20Venue(CRVUSD).allowance(address(t.va), VOTIUM), 0, "va->votium allowance");
        assertEq(IErc20Venue(CRVUSD).allowance(address(t.vma), CRM), 0, "vma->crm allowance");
        assertEq(IErc20Venue(CRVUSD).allowance(address(t.lister), FEEDIST), 0, "lister->fd allowance");
        assertEq(IErc20Venue(CRVUSD).allowance(CRM, TOKEN_FACTORY), 0, "crm->tokenfactory allowance");
    }

    // ------------------------------------------------------------------
    // Adapter receipt binding (§6.2, R8-2): the KEYED (`getDeposit` resolved
    // through `_depositIndex`) and chronological (`depositAt` on the single
    // authoritative `_depositLog` array) lookup forms expose ONE record; each
    // successful quarter binds both, plus the CampaignDeposit and per-leg
    // PlatformDeposit events. Shared by the VoteMarket runner's prover and
    // the Kill runner's mixed checkpoint.
    // Provenance (S09): a receipt is an OPAQUE adapter-domain identifier —
    // the keccak tuple below — attested only by its emitter (the adapter on
    // chain 1, via the recorded key/index pair and the CampaignDeposit /
    // VotiumDeposit event). It carries no destination-side meaning: neither
    // the hash nor the local ordinal proves an L2 campaign exists or that
    // any venue accepted a delivery.
    // ------------------------------------------------------------------

    function _assertAdapterRecord(Trio memory t, uint256 ts, uint256 gross, uint256 expectedLocalNonce) internal view {
        (uint256 amt, uint256 execEp, bytes32 receipt) = t.vma.getDeposit(GAUGE_PRIMARY, ts);
        assertEq(amt, gross, "keyed record amount");
        assertEq(execEp, ts, "keyed record execution epoch (weekly boundary)");
        assertEq(receipt, keccak256(abi.encode(GAUGE_PRIMARY, ts, gross, expectedLocalNonce)), "receipt nonce");
        assertTrue(receipt != bytes32(0), "nonzero receipt");
        VoteMarketAdapter.DepositRecord memory log0 = t.vma.depositAt(expectedLocalNonce - 1);
        assertEq(log0.gauge, GAUGE_PRIMARY, "chronological gauge");
        assertEq(log0.scheduledEpoch, ts, "chronological scheduled");
        assertEq(log0.amount, gross, "chronological amount");
        assertEq(log0.executionEpoch, ts, "chronological execution epoch (weekly boundary)");
        assertEq(log0.receipt, receipt, "chronological receipt matches keyed");
        assertEq(t.vma.depositCount(), expectedLocalNonce, "deposit count");
        // Adapter deposit nonce started at 1, independently of the bridge
        // nonce (in the thousands at this pin): receipt domains are separate.
        assertTrue(expectedLocalNonce <= 4, "local nonce ladder");
    }

    /// @dev Decode the adapter's CampaignDeposit receipt event (R8-2): topics
    /// bind gauge/scheduled/execution epochs, data binds amount + the exact
    /// nonce-domain receipt — not merely a nonzero event count.
    function _assertCampaignDepositLog(
        FVm.Log[] memory logs,
        VoteMarketAdapter vma,
        uint256 ts,
        uint256 gross,
        uint256 nonce
    ) internal pure {
        assertEq(_countLogs(logs, address(vma), T_CAMPAIGN_DEPOSIT), 1, "one CampaignDeposit event");
        bool seen;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (
                logs[i].emitter == address(vma) && logs[i].topics.length == 4 && logs[i].topics[0] == T_CAMPAIGN_DEPOSIT
            ) {
                assertEq(address(uint160(uint256(logs[i].topics[1]))), GAUGE_PRIMARY, "CampaignDeposit gauge");
                assertEq(uint256(logs[i].topics[2]), ts, "CampaignDeposit scheduled epoch");
                assertEq(uint256(logs[i].topics[3]), ts, "CampaignDeposit execution epoch");
                (uint256 amount, bytes32 receipt) = abi.decode(logs[i].data, (uint256, bytes32));
                assertEq(amount, gross, "CampaignDeposit amount");
                assertEq(receipt, keccak256(abi.encode(GAUGE_PRIMARY, ts, gross, nonce)), "CampaignDeposit receipt");
                seen = true;
            }
        }
        assertTrue(seen, "CampaignDeposit decoded");
    }

    /// @dev Decode the lister's PlatformDeposit for a specific platform leg
    /// (R8-2): topics bind gauge/platform/scheduled epoch, data binds the
    /// execution epoch, the routed amount and the exact domain receipt.
    /// Exactly one such event exists per platform leg (mixed quarters emit
    /// one for each distinct adapter).
    function _assertListerPlatformDeposit(
        FVm.Log[] memory logs,
        address lister,
        address platform,
        uint256 ts,
        uint256 amount,
        bytes32 wantReceipt
    ) internal pure {
        uint256 matches;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (
                logs[i].emitter == lister && logs[i].topics.length == 4 && logs[i].topics[0] == T_PLATFORM_DEPOSIT
                    && address(uint160(uint256(logs[i].topics[2]))) == platform
            ) {
                assertEq(address(uint160(uint256(logs[i].topics[1]))), GAUGE_PRIMARY, "deposit gauge");
                assertEq(uint256(logs[i].topics[3]), ts, "deposit scheduled epoch");
                (uint256 executionEpoch, uint256 routedAmount, bytes32 receipt) =
                    abi.decode(logs[i].data, (uint256, uint256, bytes32));
                assertEq(executionEpoch, ts, "deposit execution epoch (weekly boundary)");
                assertEq(routedAmount, amount, "deposit routed amount");
                assertEq(receipt, wantReceipt, "deposit receipt");
                matches += 1;
            }
        }
        assertEq(matches, 1, "one PlatformDeposit for this leg");
    }

    // ------------------------------------------------------------------
    // Log helpers (fork-owned, over FVm.Log)
    // ------------------------------------------------------------------

    function _countLogs(FVm.Log[] memory logs, address emitter, bytes32 topic0) internal pure returns (uint256 n) {
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].emitter == emitter && logs[i].topics.length > 0 && logs[i].topics[0] == topic0) {
                n += 1;
            }
        }
    }

    function _tokenTransferCount(FVm.Log[] memory logs, address from, address to, uint256 amount)
        internal
        pure
        returns (uint256 n)
    {
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].emitter == CRVUSD && logs[i].topics.length == 3 && logs[i].topics[0] == T_TRANSFER) {
                if (
                    address(uint160(uint256(logs[i].topics[1]))) == from
                        && address(uint160(uint256(logs[i].topics[2]))) == to && logs[i].data.length == 32
                        && abi.decode(logs[i].data, (uint256)) == amount
                ) {
                    n += 1;
                }
            }
        }
    }

    function _tokenApprovalCount(FVm.Log[] memory logs, address ownerAddr, address spender, uint256 value)
        internal
        pure
        returns (uint256 n)
    {
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].emitter == CRVUSD && logs[i].topics.length == 3 && logs[i].topics[0] == T_APPROVAL) {
                if (
                    address(uint160(uint256(logs[i].topics[1]))) == ownerAddr
                        && address(uint160(uint256(logs[i].topics[2]))) == spender && logs[i].data.length == 32
                        && abi.decode(logs[i].data, (uint256)) == value
                ) {
                    n += 1;
                }
            }
        }
    }

    /// @dev CX-FORK-TRACE: complete, OWNER/SPENDER-SCOPED per-leg approval
    /// evidence. Value-filtered counts alone do not bound every observed
    /// approval — an unaccounted value for the SAME pair slips through a
    /// count-only check. This helper asserts the full trace of the
    /// (`ownerAddr`, `spender`) pair: every observed Approval event must
    /// match one expected value with exact multiplicity, and every expected
    /// value must be observed exactly once. Legitimate token-generated
    /// decrements (the allowance-consumption zero emitted by the venue's own
    /// transferFrom) are EXPECTED MEMBERS of the trace, never filtered out.
    /// This is bounded-approval ingress evidence for the product-owned leg:
    /// it is not proof of venue delivery, and the final cleared allowance
    /// stays asserted separately (`_assertZeroApprovals`).
    function _assertApprovalTrace(
        FVm.Log[] memory logs,
        address ownerAddr,
        address spender,
        uint256[] memory expectedValues,
        string memory label
    ) internal pure {
        bool[] memory used = new bool[](expectedValues.length);
        uint256 seen;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (
                logs[i].emitter == CRVUSD && logs[i].topics.length == 3 && logs[i].topics[0] == T_APPROVAL
                    && address(uint160(uint256(logs[i].topics[1]))) == ownerAddr
                    && address(uint160(uint256(logs[i].topics[2]))) == spender
            ) {
                require(logs[i].data.length == 32, string.concat(label, ": Approval data not one word"));
                uint256 v = abi.decode(logs[i].data, (uint256));
                bool matched;
                for (uint256 j = 0; j < expectedValues.length; ++j) {
                    if (!used[j] && expectedValues[j] == v) {
                        used[j] = true;
                        matched = true;
                        break;
                    }
                }
                require(matched, string.concat(label, ": approval value outside the bounded expected trace"));
                seen += 1;
            }
        }
        require(seen == expectedValues.length, string.concat(label, ": bounded trace multiplicity"));
    }

    // ------------------------------------------------------------------
    // Votium incentive inspection (§6.1)
    // ------------------------------------------------------------------

    /// @dev Assert one real incentive at (round, gauge, index) was appended
    /// by the bound VotiumAdapter with the exact gross/net/fee split.
    function _assertIncentive(address adapterAddr, uint256 round, uint256 index, uint256 gross) internal view {
        uint256 fee = (gross * IVotiumVenue(VOTIUM).platformFee()) / IVotiumVenue(VOTIUM).DENOMINATOR();
        VenueIncentive memory inc = IVotiumVenue(VOTIUM).viewIncentive(round, GAUGE_PRIMARY, index);
        assertEq(inc.token, CRVUSD, "incentive token = crvUSD");
        assertEq(inc.amount, gross - fee, "incentive amount = gross - platform fee");
        assertEq(inc.maxPerVote, 0, "maxPerVote default 0");
        assertEq(inc.distributed, 0, "distributed 0");
        assertEq(inc.recycled, 0, "recycled 0");
        assertEq(inc.depositor, adapterAddr, "depositor is the bound VotiumAdapter");
        assertEq(inc.excluded.length, 0, "exclusions empty");
    }

    /// @dev Votium venue reconciliation for one deposit: net to Votium, fee
    /// to the real fee address, NET + FEE = GROSS (§6.1 gross/net law).
    function _assertVotiumDeltas(Snap memory pre, Snap memory post, uint256 gross) internal view {
        uint256 fee = (gross * IVotiumVenue(VOTIUM).platformFee()) / IVotiumVenue(VOTIUM).DENOMINATOR();
        assertEq(post.votiumCrv - pre.votiumCrv, gross - fee, "votium net increase");
        assertEq(post.feeCrv - pre.feeCrv, fee, "fee address increase");
        assertEq((post.votiumCrv - pre.votiumCrv) + (post.feeCrv - pre.feeCrv), gross, "net + fee = gross");
        assertEq(post.virtualCrv - pre.virtualCrv, gross - fee, "virtual balance net increase");
    }

    // ------------------------------------------------------------------
    // Votium leg: exact deposit call + bounded-approval proof (§6, R8-1).
    // Final zero allowances alone do not prove bounded approvals; the exact
    // approval/transfer amounts and the exact venue call are asserted here.
    // ------------------------------------------------------------------

    /// @dev Expect the adapter's EXACT `depositUnevenSplitGauges` call:
    /// crvUSD, the live round, single-element gauge and gross arrays, default
    /// maxPerVote 0 and empty exclusions. (This Forge's plain expectCall is
    /// at-least-once with exact data, so one declaration covers both the
    /// single-quarter and the four-in-one-checkpoint catch-up; exact
    /// multiplicity is pinned by `_assertVotiumLegEvents` log counts.)
    function _expectVotiumDeposit(uint256 round, uint256 gross) internal {
        address[] memory gauges = new address[](1);
        gauges[0] = GAUGE_PRIMARY;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = gross;
        fvm.expectCall(
            VOTIUM,
            abi.encodeCall(
                IVotiumVenue.depositUnevenSplitGauges, (CRVUSD, round, gauges, amounts, uint256(0), new address[](0))
            )
        );
    }

    /// @dev Exact Votium-side Approval/Transfer evidence for `times` deposits
    /// of `gross`: the pull (lister->adapter), the venue's own net/fee
    /// transfers out of the adapter, and the adapter's bounded-approval
    /// lifecycle as a COMPLETE owner/spender-scoped trace (CX-FORK-TRACE).
    /// `forceApprove` is zero-then-exact with the zero request collapsed to
    /// ONE checked zero approval (SafeToken), so per deposit the
    /// lister->adapter pair shows the zero reset, the EXACT-gross set and
    /// the legitimate token-generated allowance-zero from the adapter's own
    /// transferFrom ([0, gross, 0]); the adapter->venue pair adds the single
    /// post-deposit clear ([0, gross, 0, 0]). Bounding the full trace —
    /// exact multiplicity over every observed value, including a standing
    /// unlimited approval, which would match no expected entry (R8-1) —
    /// replaces the value-filtered counts: a count of one value does not
    /// bound the others. This is ingress/custody evidence only, not proof of
    /// venue delivery; the final cleared allowances stay asserted separately
    /// by the callers' `_assertZeroApprovals`.
    function _assertVotiumLegEvents(Trio memory t, FVm.Log[] memory logs, uint256 gross, uint64 times) internal view {
        uint256 fee = (gross * IVotiumVenue(VOTIUM).platformFee()) / IVotiumVenue(VOTIUM).DENOMINATOR();
        assertEq(
            _tokenTransferCount(logs, address(t.lister), address(t.va), gross),
            times,
            "votium leg: pull lister->adapter"
        );
        assertEq(
            _tokenTransferCount(logs, address(t.va), IVotiumVenue(VOTIUM).feeAddress(), fee),
            times,
            "votium leg: exact fee transfer"
        );
        assertEq(_tokenTransferCount(logs, address(t.va), VOTIUM, gross - fee), times, "votium leg: exact net transfer");
        uint256[] memory listerPair = new uint256[](3 * uint256(times));
        uint256[] memory venuePair = new uint256[](4 * uint256(times));
        for (uint256 d = 0; d < uint256(times); ++d) {
            listerPair[3 * d] = 0;
            listerPair[3 * d + 1] = gross;
            listerPair[3 * d + 2] = 0;
            venuePair[4 * d] = 0;
            venuePair[4 * d + 1] = gross;
            venuePair[4 * d + 2] = 0;
            venuePair[4 * d + 3] = 0;
        }
        _assertApprovalTrace(logs, address(t.lister), address(t.va), listerPair, "votium leg: lister approval trace");
        _assertApprovalTrace(logs, address(t.va), VOTIUM, venuePair, "votium leg: bounded approval trace");
    }

    // ------------------------------------------------------------------
    // No-op rejection (§6, R8-2): repeated/terminal settlement emits no new
    // settlement events and writes no new receipts.
    // ------------------------------------------------------------------

    function _assertNoSettlementEvents(FVm.Log[] memory logs, Trio memory t) internal pure {
        assertEq(_countLogs(logs, address(t.lister), T_QUARTER_RELEASED), 0, "no-op: no QuarterReleased");
        assertEq(_countLogs(logs, address(t.lister), T_PLATFORM_DEPOSIT), 0, "no-op: no PlatformDeposit");
        assertEq(_countLogs(logs, address(t.lister), T_ESCROW_CONFISCATED), 0, "no-op: no EscrowConfiscated");
        assertEq(_countLogs(logs, address(t.lister), T_FEE_CHECKPOINT_RESULT), 0, "no-op: no FeeCheckpointResult");
        assertEq(_countLogs(logs, address(t.va), T_VOTIUM_DEPOSIT), 0, "no-op: no VotiumDeposit receipt");
        assertEq(_countLogs(logs, address(t.vma), T_CAMPAIGN_DEPOSIT), 0, "no-op: no CampaignDeposit receipt");
        assertEq(_countLogs(logs, VOTIUM, T_NEW_INCENTIVE), 0, "no-op: no venue incentive");
        assertEq(_countLogs(logs, LA_POSTE, T_MESSAGE_SENT), 0, "no-op: no bridge message");
        assertEq(_countLogs(logs, CRM, T_CAMPAIGN_PAYLOAD_SENT), 0, "no-op: no CRM payload event");
    }

    // ------------------------------------------------------------------
    // Kill-path event decoding + actual checkpoint outcome (§6.3, R8-2)
    // ------------------------------------------------------------------

    /// @dev Decode the single EscrowConfiscated: fixed FD destination, exact
    /// amount and the receipt week (epochStart of the kill timestamp).
    function _assertEscrowConfiscated(FVm.Log[] memory logs, address lister, uint256 wantAmount, uint256 wantWeek)
        internal
        pure
    {
        assertEq(_countLogs(logs, lister, T_ESCROW_CONFISCATED), 1, "one EscrowConfiscated");
        bool seen;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].emitter == lister && logs[i].topics.length == 3 && logs[i].topics[0] == T_ESCROW_CONFISCATED) {
                assertEq(address(uint160(uint256(logs[i].topics[1]))), GAUGE_PRIMARY, "confiscation gauge");
                assertEq(address(uint160(uint256(logs[i].topics[2]))), FEEDIST, "fixed destination FD");
                (uint256 amount, uint256 receiptWeek) = abi.decode(logs[i].data, (uint256, uint256));
                assertEq(amount, wantAmount, "confiscated amount");
                assertEq(receiptWeek, wantWeek, "receipt week = epochStart(kill timestamp)");
                seen = true;
            }
        }
        assertTrue(seen, "EscrowConfiscated decoded");
    }

    /// @dev Expected outcome of the lister's MANDATORY in-confiscation FD
    /// accounting (auditfix001 §3/§7), rebound to the SELECTED allocator's
    /// actual source and runtime (S02; docs/DEPLOYMENT-PINS.md records the
    /// admin, public-checkpoint flag, cursor, accounted balance, custody and
    /// the bounded-loop source at the verified runtime): the real
    /// `CurveFeeDistribution.vy` caller rule — `can_checkpoint_token` AND
    /// strict `block.timestamp > last_token_time + 86400` for a non-admin
    /// caller (the lister is not FD.admin, so no admin bypass applies) —
    /// PLUS the §3 COVERAGE predicate: the cursor must be nonzero, not in the
    /// future, and within the core's named 20-week accounting horizon
    /// (`FD_ACCOUNTING_HORIZON_WEEKS`, mirrored by the mock allocator's
    /// bounded loop) of the cursor's week floor. Availability (cooldown) and
    /// coverage are separate; neither implies the other. Read live BEFORE the
    /// call; a successful checkpoint mutates last_token_time. If this returns
    /// false, a confiscation attempt must REVERT (escrow retained).
    function _expectedFdCheckpointOk() internal view returns (bool) {
        uint256 t = IFdVenue(FEEDIST).last_token_time();
        bool fresh = t != 0 && t <= block.timestamp && block.timestamp - (t / WEEK) * WEEK <= 20 * WEEK;
        return IFdVenue(FEEDIST).can_checkpoint_token() && block.timestamp > t + 86400 && fresh;
    }

    /// @dev Assert the ACTUAL FeeCheckpointResult outcome of a settlement:
    /// exactly one event, equal to the live-law expectation.
    function _assertFeeCheckpointResult(FVm.Log[] memory logs, address lister, bool wantOk, string memory label)
        internal
        pure
    {
        assertEq(
            _countLogs(logs, lister, T_FEE_CHECKPOINT_RESULT), 1, string.concat(label, ": one FeeCheckpointResult")
        );
        bool seen;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].emitter == lister && logs[i].topics.length == 1 && logs[i].topics[0] == T_FEE_CHECKPOINT_RESULT)
            {
                (bool okFlag) = abi.decode(logs[i].data, (bool));
                assertTrue(
                    okFlag == wantOk,
                    string.concat(
                        label, wantOk ? ": expected FeeCheckpointResult(true)" : ": expected FeeCheckpointResult(false)"
                    )
                );
                seen = true;
            }
        }
        assertTrue(seen, string.concat(label, ": FeeCheckpointResult decoded"));
    }

    // ------------------------------------------------------------------
    // Candidate provenance (§4/§5.3, R8-4): read-only checks re-run INSIDE
    // every fixture before any seating/funding write.
    // ------------------------------------------------------------------

    /// @dev One candidate: authentic factory pool/gauge/LP association, live
    /// flag, 2–8 immediate nonzero distinct coins, valid handler/index/type,
    /// genuine absence from the controller (empty-data revert distinguished
    /// from transport failure) and pinned runtime code hashes.
    function _assertCandidateProvenance(
        address pool,
        address gauge,
        address coin0,
        address coin1,
        bytes32 gaugeHash,
        bytes32 poolHash
    ) internal {
        IMetaRegistryVenue reg = IMetaRegistryVenue(METAREGISTRY);
        assertTrue(reg.is_registered(pool, HANDLER_ID), "pool registered");
        assertEq(reg.get_lp_token(pool, HANDLER_ID), pool, "lp token = pool");
        assertEq(reg.get_gauge(pool, GAUGE_INDEX, HANDLER_ID), gauge, "gauge at (0,0)");
        _assertI128Eq(reg.get_gauge_type(pool, GAUGE_INDEX, HANDLER_ID), int128(0), "type 0");
        assertEq(reg.get_n_coins(pool, HANDLER_ID), 2, "two coins");
        address[8] memory coins = reg.get_coins(pool, HANDLER_ID);
        assertEq(coins[0], coin0, "coin 0");
        assertEq(coins[1], coin1, "coin 1");
        assertEq(coins[2], address(0), "coin slots beyond n are zero");
        assertTrue(coins[0].code.length > 0 && coins[1].code.length > 0, "coins have code");
        assertTrue(coins[0] != coins[1], "coins distinct");
        IGaugeVenue g = IGaugeVenue(gauge);
        assertEq(g.lp_token(), pool, "gauge lp association");
        assertFalse(g.is_killed(), "live flag false");
        assertEq(g.factory(), FACTORY, "authentic factory association");
        assertEq(keccak256(gauge.code), gaugeHash, "gauge runtime hash");
        assertEq(gauge.code.length, 10725, "gauge runtime size");
        assertEq(keccak256(pool.code), poolHash, "pool runtime hash");

        // Genuine absence: gauge_types must revert with EMPTY data (absent
        // gauge), never a value and never non-empty data.
        try IControllerVenue(CONTROLLER).gauge_types(gauge) returns (int128 absentTy) {
            assertTrue(false, "gauge unexpectedly already registered");
        } catch (bytes memory ret) {
            assertEq(uint256(ret.length), 0, "absence is an empty EVM revert, not transport/other");
        }
    }

    /// @dev §4/§5.3 pre-write fixture provenance for the primary candidate
    /// plus its kill-authority bindings; runs inside `_deployTrio`/
    /// `_deployTrioAltVm`, i.e. before any seating, funding or listing write
    /// (R8-4).
    function _assertPrimaryProvenance() internal {
        _assertCandidateProvenance(POOL_PRIMARY, GAUGE_PRIMARY, COIN_P0, COIN_P1, H_GAUGE_PRIMARY, H_POOL_PRIMARY);
        assertEq(IFactoryVenue(FACTORY).admin(), AMM_PROXY, "fixture: factory admin is the AMM owner proxy");
        assertEq(IProxyVenue(AMM_PROXY).dao(), DAO, "fixture: proxy dao");
        assertEq(IProxyVenue(AMM_PROXY).emergency_dao(), EMERGENCY_DAO, "fixture: proxy emergency agent");
        assertEq(keccak256(CONTROLLER.code), H_CONTROLLER, "fixture: controller code");
        assertEq(keccak256(METAREGISTRY.code), H_META, "fixture: metaregistry code");
        assertEq(keccak256(CRVUSD.code), H_CRVUSD, "fixture: crvUSD code");
        assertEq(keccak256(FEEDIST.code), H_FD, "fixture: FD code");
        assertEq(keccak256(VOTIUM.code), H_VOTIUM, "fixture: votium code");
        assertEq(keccak256(CRM.code), H_CRM, "fixture: crm code");
    }

    // ------------------------------------------------------------------
    // LaPoste message decoding (§6.2)
    // ------------------------------------------------------------------

    struct LpToken {
        address tokenAddress;
        uint256 amount;
    }

    struct LpMeta {
        string name;
        string symbol;
        uint8 decimals;
    }

    struct LpMessage {
        uint256 destinationChainId;
        address to;
        address sender;
        LpToken[] tokens;
        LpMeta[] tokenMetadata;
        bytes payload;
        uint256 nonce;
    }

    struct CrmPayload {
        uint8 actionType;
        address sender;
        address votemarket;
        bytes parameters;
    }

    /// @dev Extract the first real MessageSent log emitted by LaPoste.
    function _requireMessageSent(FVm.Log[] memory logs)
        internal
        pure
        returns (bytes32 nonceTopic, bytes32 senderTopic, address to, LpMessage memory message)
    {
        bool found;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].emitter == LA_POSTE && logs[i].topics.length == 4 && logs[i].topics[0] == T_MESSAGE_SENT) {
                require(!found, "duplicate MessageSent in one message proof");
                nonceTopic = logs[i].topics[2];
                senderTopic = logs[i].topics[3];
                (to, message) = abi.decode(logs[i].data, (address, LpMessage));
                found = true;
            }
        }
        assertTrue(found, "real LaPoste MessageSent emitted");
    }

    /// @dev Decode and fully bind the campaign message payload (§6.2).
    function _assertCampaignMessage(
        LpMessage memory message,
        uint256 expectedNonce,
        address managerAdapter,
        uint256 totalRewardAmount
    ) internal view {
        assertEq(message.destinationChainId, VM_DEST_CHAIN_ID, "message destination chain");
        assertEq(message.to, CRM, "message to = CRM");
        assertEq(message.sender, CRM, "message sender = CRM (LaPoste msg.sender)");
        assertEq(message.nonce, expectedNonce, "message nonce");
        assertEq(message.tokens.length, 1, "one token leg");
        assertEq(message.tokens[0].tokenAddress, CRVUSD, "locked token = crvUSD");
        assertEq(message.tokens[0].amount, totalRewardAmount, "locked amount");
        assertEq(message.tokenMetadata.length, 1, "one metadata leg");
        (string memory nm, string memory sy, uint8 dec) = ITokenFactoryVenue(TOKEN_FACTORY).getTokenMetadata(CRVUSD);
        _assertStringEq(message.tokenMetadata[0].name, nm, "real tokenFactory metadata name");
        _assertStringEq(message.tokenMetadata[0].symbol, sy, "real tokenFactory metadata symbol");
        assertEq(uint256(message.tokenMetadata[0].decimals), uint256(dec), "real tokenFactory metadata decimals");
        assertTrue(bytes(message.tokenMetadata[0].name).length > 0, "metadata name nonempty");
        assertEq(uint256(dec), 18, "crvUSD metadata decimals");

        CrmPayload memory payload = abi.decode(message.payload, (CrmPayload));
        assertEq(uint256(payload.actionType), 0, "action CREATE_CAMPAIGN");
        assertEq(payload.sender, managerAdapter, "payload sender = adapter");
        assertEq(payload.votemarket, VM_DESTINATION, "payload destination platform");

        ICrmmVenue.CampaignParams memory p = abi.decode(payload.parameters, (ICrmmVenue.CampaignParams));
        assertEq(p.chainId, FORK_CHAIN_ID, "campaign params source chain 1");
        assertEq(p.gauge, GAUGE_PRIMARY, "campaign params gauge");
        assertEq(p.manager, managerAdapter, "campaign params manager = local adapter");
        assertEq(p.rewardToken, CRVUSD, "campaign params reward token");
        assertEq(uint256(p.numberOfPeriods), 2, "campaign params two periods");
        assertEq(p.maxRewardPerVote, type(uint256).max, "configured positive cap");
        assertEq(p.totalRewardAmount, totalRewardAmount, "campaign gross");
        assertEq(p.addresses.length, 0, "empty exclusion addresses");
        assertEq(p.hook, address(0), "zero hook");
        assertFalse(p.isWhitelist, "no whitelist campaign");
    }

    // ------------------------------------------------------------------
    // R8-3: exact downstream message reconstruction for independent router
    // reconciliation. The CRM params, LaPoste message and GasBadger CCIP
    // EVM2AnyMessage are all deterministic from pinned state; rebuilding them
    // from the verified deployed semantics lets the suite live-quote the real
    // router and bind the adapter's own getFee/ccipSend calls (no mocks, no
    // hardcoded fee).
    // ------------------------------------------------------------------

    /// @dev The exact CampaignParams the local adapter will pass (mirrors
    /// VoteMarketAdapter.deposit; every input is read live).
    function _expectedCampaignParams(VoteMarketAdapter vma, uint256 gross)
        internal
        view
        returns (ICrmmVenue.CampaignParams memory p)
    {
        p.chainId = FORK_CHAIN_ID;
        p.gauge = GAUGE_PRIMARY;
        p.manager = address(vma);
        p.rewardToken = CRVUSD;
        p.numberOfPeriods = 2;
        p.maxRewardPerVote = vma.maxRewardPerVote();
        p.totalRewardAmount = gross;
        p.addresses = new address[](0);
        p.hook = address(0);
        p.isWhitelist = false;
    }

    /// @dev The exact ILaPoste.Message the CRM will hand to LaPoste: CRM is
    /// both `to` (destination platform receiver) and `sender` (LaPoste caller)
    /// per the deployed CRM, the token leg and metadata come from the real
    /// TokenFactory, the payload is the CRM CREATE_CAMPAIGN tuple and the
    /// nonce is the next live sentNonces value.
    function _expectedLaposteMessage(VoteMarketAdapter vma, uint256 gross) internal view returns (LpMessage memory m) {
        m.destinationChainId = VM_DEST_CHAIN_ID;
        m.to = CRM;
        m.sender = CRM;
        m.tokens = new LpToken[](1);
        m.tokens[0].tokenAddress = CRVUSD;
        m.tokens[0].amount = gross;
        (string memory nm, string memory sy, uint8 dec) = ITokenFactoryVenue(TOKEN_FACTORY).getTokenMetadata(CRVUSD);
        m.tokenMetadata = new LpMeta[](1);
        m.tokenMetadata[0].name = nm;
        m.tokenMetadata[0].symbol = sy;
        m.tokenMetadata[0].decimals = dec;
        CrmPayload memory payload;
        payload.actionType = 0; // CREATE_CAMPAIGN
        payload.sender = address(vma);
        payload.votemarket = VM_DESTINATION;
        payload.parameters = abi.encode(_expectedCampaignParams(vma, gross));
        m.payload = abi.encode(payload);
        m.nonce = ILaPosteVenue(LA_POSTE).sentNonces(VM_DEST_CHAIN_ID) + 1;
    }

    /// @dev The exact Client.EVM2AnyMessage the GasBadger CCIP adapter sends:
    /// LaPoste delegatecalls it with `to` = the adapter's own CREATE3-same
    /// remote address and `data` = abi.encode(laPosteMessage); no CCIP token
    /// amounts (custody is the TokenFactory lock); feeToken zero (native);
    /// extraArgs = tag + abi.encode(additionalGas + real BASE_GAS_LIMIT).
    function _buildCcipMessage(LpMessage memory laposte)
        internal
        view
        returns (IRouterVenue.CcipEvm2AnyMessage memory m)
    {
        m.receiver = abi.encode(CCIP_ADAPTER);
        m.data = abi.encode(laposte);
        m.tokenAmounts = new IRouterVenue.CcipTokenAmount[](0);
        m.feeToken = address(0);
        m.extraArgs = abi.encodePacked(
            CCIP_EXTRA_ARGS_TAG, abi.encode(CAMPAIGN_CREATION_GAS + ICcipAdapterVenue(CCIP_ADAPTER).BASE_GAS_LIMIT())
        );
    }
}
