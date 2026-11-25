// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {TestBase, Vm} from "../TestBase.sol";
import {GaugeControllerAdmin} from "../../contracts/GaugeControllerAdmin.sol";
import {RouterControllerMock, RouterDaoShim, RouterAdderShim, RouterVm} from "./RouterMocks.sol";

/// @dev Shared harness for the GaugeControllerAdmin offline matrix: fresh-
/// artifact JSON introspection, low-level call helpers, and role fixtures.
/// Abstract with ZERO test functions (matrix evidence rules); concrete test
/// contracts inherit it. Public tests are self-contained: the normative ABI/
/// layout manifest is embedded verbatim below as a hex literal produced from
/// plans/ROUTERPLAN-ABI.json (compact serialization, derivation sha256
/// e9975e94c7492417d0e544552a3f6d9a0f213abc443220064b433093ffaccddb, recorded with the candidate receipts), and every
/// comparison reads the FRESH artifact under out/ written by this very forge
/// build.
abstract contract RouterHarness is TestBase {
    RouterVm internal constant rv = RouterVm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    /// @dev Compact JSON of the normative router ABI/layout manifest.
    string internal constant MANIFEST_JSON = string(
        hex"7b22736368656d61223a22726f75746572706c616e2d6e65772d6162692d6c61796f75742d7631222c2273636f7065223a224e6f726d6174697665204e455720726f75746572204142492f6c61796f7574206f6e6c793b206e6f206578697374696e67206d616e6966657374206973207265706c61636564222c22616269223a5b7b2274797065223a22636f6e7374727563746f72222c22696e70757473223a5b7b226e616d65223a22636f6e74726f6c6c65725f222c2274797065223a2261646472657373222c22696e7465726e616c54797065223a2261646472657373227d2c7b226e616d65223a2264616f5f222c2274797065223a2261646472657373222c22696e7465726e616c54797065223a2261646472657373227d5d2c2273746174654d75746162696c697479223a226e6f6e70617961626c65227d2c7b2274797065223a2266756e6374696f6e222c226e616d65223a226164645f6761756765222c22696e70757473223a5b7b226e616d65223a226761756765222c2274797065223a2261646472657373222c22696e7465726e616c54797065223a2261646472657373227d2c7b226e616d65223a22676175676554797065222c2274797065223a22696e74313238222c22696e7465726e616c54797065223a22696e74313238227d2c7b226e616d65223a22776569676874222c2274797065223a2275696e74323536222c22696e7465726e616c54797065223a2275696e74323536227d5d2c226f757470757473223a5b5d2c2273746174654d75746162696c697479223a226e6f6e70617961626c65227d2c7b2274797065223a2266756e6374696f6e222c226e616d65223a226170706c795f7472616e736665725f6f776e657273686970222c22696e70757473223a5b5d2c226f757470757473223a5b5d2c2273746174654d75746162696c697479223a226e6f6e70617961626c65227d2c7b2274797065223a2266756e6374696f6e222c226e616d65223a22636f6d6d69745f7472616e736665725f6f776e657273686970222c22696e70757473223a5b7b226e616d65223a22737563636573736f72222c2274797065223a2261646472657373222c22696e7465726e616c54797065223a2261646472657373227d5d2c226f757470757473223a5b5d2c2273746174654d75746162696c697479223a226e6f6e70617961626c65227d2c7b2274797065223a2266756e6374696f6e222c226e616d65223a22636f6e74726f6c6c6572222c22696e70757473223a5b5d2c226f757470757473223a5b7b226e616d65223a22222c2274797065223a2261646472657373222c22696e7465726e616c54797065223a2261646472657373227d5d2c2273746174654d75746162696c697479223a2276696577227d2c7b2274797065223a2266756e6374696f6e222c226e616d65223a2264616f222c22696e70757473223a5b5d2c226f757470757473223a5b7b226e616d65223a22222c2274797065223a2261646472657373222c22696e7465726e616c54797065223a2261646472657373227d5d2c2273746174654d75746162696c697479223a2276696577227d2c7b2274797065223a2266756e6374696f6e222c226e616d65223a2265786563757465222c22696e70757473223a5b7b226e616d65223a2264617461222c2274797065223a226279746573222c22696e7465726e616c54797065223a226279746573227d5d2c226f757470757473223a5b7b226e616d65223a22726573756c74222c2274797065223a226279746573222c22696e7465726e616c54797065223a226279746573227d5d2c2273746174654d75746162696c697479223a226e6f6e70617961626c65227d2c7b2274797065223a2266756e6374696f6e222c226e616d65223a2267617567655f7479706573222c22696e70757473223a5b7b226e616d65223a226761756765222c2274797065223a2261646472657373222c22696e7465726e616c54797065223a2261646472657373227d5d2c226f757470757473223a5b7b226e616d65223a22222c2274797065223a22696e74313238222c22696e7465726e616c54797065223a22696e74313238227d5d2c2273746174654d75746162696c697479223a2276696577227d2c7b2274797065223a2266756e6374696f6e222c226e616d65223a226772616e74222c22696e70757473223a5b7b226e616d65223a226164646572222c2274797065223a2261646472657373222c22696e7465726e616c54797065223a2261646472657373227d2c7b226e616d65223a22656e61626c6564222c2274797065223a22626f6f6c222c22696e7465726e616c54797065223a22626f6f6c227d5d2c226f757470757473223a5b5d2c2273746174654d75746162696c697479223a226e6f6e70617961626c65227d2c7b2274797065223a2266756e6374696f6e222c226e616d65223a2269734164646572222c22696e70757473223a5b7b226e616d65223a22222c2274797065223a2261646472657373222c22696e7465726e616c54797065223a2261646472657373227d5d2c226f757470757473223a5b7b226e616d65223a22222c2274797065223a22626f6f6c222c22696e7465726e616c54797065223a22626f6f6c227d5d2c2273746174654d75746162696c697479223a2276696577227d2c7b2274797065223a2266756e6374696f6e222c226e616d65223a226e5f67617567655f7479706573222c22696e70757473223a5b5d2c226f757470757473223a5b7b226e616d65223a22222c2274797065223a22696e74313238222c22696e7465726e616c54797065223a22696e74313238227d5d2c2273746174654d75746162696c697479223a2276696577227d2c7b2274797065223a2266756e6374696f6e222c226e616d65223a2270656e64696e67436f6e74726f6c6c657241646d696e222c22696e70757473223a5b5d2c226f757470757473223a5b7b226e616d65223a22222c2274797065223a2261646472657373222c22696e7465726e616c54797065223a2261646472657373227d5d2c2273746174654d75746162696c697479223a2276696577227d2c7b2274797065223a2266756e6374696f6e222c226e616d65223a2272657469726564222c22696e70757473223a5b5d2c226f757470757473223a5b7b226e616d65223a22222c2274797065223a22626f6f6c222c22696e7465726e616c54797065223a22626f6f6c227d5d2c2273746174654d75746162696c697479223a2276696577227d2c7b2274797065223a226576656e74222c226e616d65223a224164646572536574222c22696e70757473223a5b7b226e616d65223a226164646572222c2274797065223a2261646472657373222c22696e6465786564223a747275652c22696e7465726e616c54797065223a2261646472657373227d2c7b226e616d65223a22656e61626c6564222c2274797065223a22626f6f6c222c22696e6465786564223a66616c73652c22696e7465726e616c54797065223a22626f6f6c227d5d2c22616e6f6e796d6f7573223a66616c73657d2c7b2274797065223a226576656e74222c226e616d65223a22436f6e74726f6c6c65725472616e736665724170706c696564222c22696e70757473223a5b7b226e616d65223a22737563636573736f72222c2274797065223a2261646472657373222c22696e6465786564223a747275652c22696e7465726e616c54797065223a2261646472657373227d5d2c22616e6f6e796d6f7573223a66616c73657d2c7b2274797065223a226576656e74222c226e616d65223a22436f6e74726f6c6c65725472616e73666572436f6d6d6974746564222c22696e70757473223a5b7b226e616d65223a22737563636573736f72222c2274797065223a2261646472657373222c22696e6465786564223a747275652c22696e7465726e616c54797065223a2261646472657373227d5d2c22616e6f6e796d6f7573223a66616c73657d2c7b2274797065223a226576656e74222c226e616d65223a224578656375746564222c22696e70757473223a5b7b226e616d65223a2273656c6563746f72222c2274797065223a22627974657334222c22696e6465786564223a747275652c22696e7465726e616c54797065223a22627974657334227d2c7b226e616d65223a2263616c6c6461746148617368222c2274797065223a2262797465733332222c22696e6465786564223a66616c73652c22696e7465726e616c54797065223a2262797465733332227d2c7b226e616d65223a2272657475726e6461746148617368222c2274797065223a2262797465733332222c22696e6465786564223a66616c73652c22696e7465726e616c54797065223a2262797465733332227d5d2c22616e6f6e796d6f7573223a66616c73657d2c7b2274797065223a226576656e74222c226e616d65223a2247617567654164646564222c22696e70757473223a5b7b226e616d65223a2263616c6c6572222c2274797065223a2261646472657373222c22696e6465786564223a747275652c22696e7465726e616c54797065223a2261646472657373227d2c7b226e616d65223a226761756765222c2274797065223a2261646472657373222c22696e6465786564223a747275652c22696e7465726e616c54797065223a2261646472657373227d2c7b226e616d65223a22676175676554797065222c2274797065223a22696e74313238222c22696e6465786564223a66616c73652c22696e7465726e616c54797065223a22696e74313238227d2c7b226e616d65223a22776569676874222c2274797065223a2275696e74323536222c22696e6465786564223a66616c73652c22696e7465726e616c54797065223a2275696e74323536227d5d2c22616e6f6e796d6f7573223a66616c73657d2c7b2274797065223a226572726f72222c226e616d65223a22436f6e74726f6c6c657241646d696e4d69736d61746368222c22696e70757473223a5b7b226e616d65223a226578706563746564222c2274797065223a2261646472657373222c22696e7465726e616c54797065223a2261646472657373227d2c7b226e616d65223a2261637475616c222c2274797065223a2261646472657373222c22696e7465726e616c54797065223a2261646472657373227d5d7d2c7b2274797065223a226572726f72222c226e616d65223a22496e76616c69644164646572222c22696e70757473223a5b7b226e616d65223a226164646572222c2274797065223a2261646472657373222c22696e7465726e616c54797065223a2261646472657373227d5d7d2c7b2274797065223a226572726f72222c226e616d65223a22496e76616c6964436f6e74726f6c6c6572222c22696e70757473223a5b7b226e616d65223a22636f6e74726f6c6c6572222c2274797065223a2261646472657373222c22696e7465726e616c54797065223a2261646472657373227d5d7d2c7b2274797065223a226572726f72222c226e616d65223a22496e76616c696444616f222c22696e70757473223a5b7b226e616d65223a2264616f222c2274797065223a2261646472657373222c22696e7465726e616c54797065223a2261646472657373227d5d7d2c7b2274797065223a226572726f72222c226e616d65223a22496e76616c69644f776e65727368697043616c6c64617461222c22696e70757473223a5b5d7d2c7b2274797065223a226572726f72222c226e616d65223a22496e76616c6964537563636573736f72222c22696e70757473223a5b7b226e616d65223a22737563636573736f72222c2274797065223a2261646472657373222c22696e7465726e616c54797065223a2261646472657373227d5d7d2c7b2274797065223a226572726f72222c226e616d65223a224e6f436f6465222c22696e70757473223a5b7b226e616d65223a22746172676574222c2274797065223a2261646472657373222c22696e7465726e616c54797065223a2261646472657373227d5d7d2c7b2274797065223a226572726f72222c226e616d65223a224e6f50656e64696e675472616e73666572222c22696e70757473223a5b5d7d2c7b2274797065223a226572726f72222c226e616d65223a224e6f744164646572222c22696e70757473223a5b7b226e616d65223a2263616c6c6572222c2274797065223a2261646472657373222c22696e7465726e616c54797065223a2261646472657373227d5d7d2c7b2274797065223a226572726f72222c226e616d65223a224e6f74436f6e74726f6c6c657241646d696e222c22696e70757473223a5b7b226e616d65223a2261637475616c222c2274797065223a2261646472657373222c22696e7465726e616c54797065223a2261646472657373227d5d7d2c7b2274797065223a226572726f72222c226e616d65223a224e6f7444616f222c22696e70757473223a5b7b226e616d65223a2263616c6c6572222c2274797065223a2261646472657373222c22696e7465726e616c54797065223a2261646472657373227d5d7d2c7b2274797065223a226572726f72222c226e616d65223a2250656e64696e6741646d696e4d69736d61746368222c22696e70757473223a5b7b226e616d65223a226578706563746564222c2274797065223a2261646472657373222c22696e7465726e616c54797065223a2261646472657373227d2c7b226e616d65223a2261637475616c222c2274797065223a2261646472657373222c22696e7465726e616c54797065223a2261646472657373227d5d7d2c7b2274797065223a226572726f72222c226e616d65223a225265656e7472616e7443616c6c222c22696e70757473223a5b5d7d2c7b2274797065223a226572726f72222c226e616d65223a2252657469726564222c22696e70757473223a5b5d7d5d2c226d6574686f644964656e74696669657273223a7b226164645f676175676528616464726573732c696e743132382c75696e7432353629223a223138646665393231222c226170706c795f7472616e736665725f6f776e6572736869702829223a223661316330356165222c22636f6d6d69745f7472616e736665725f6f776e657273686970286164647265737329223a223662343431613430222c22636f6e74726f6c6c65722829223a226637376334373931222c2264616f2829223a223431363231363966222c226578656375746528627974657329223a223039633565616265222c2267617567655f7479706573286164647265737329223a223366393039356237222c226772616e7428616464726573732c626f6f6c29223a223766643130313032222c2269734164646572286164647265737329223a226531663266633164222c226e5f67617567655f74797065732829223a223966626130336131222c2270656e64696e67436f6e74726f6c6c657241646d696e2829223a223262376130376338222c22726574697265642829223a223265623338616530227d2c22696d6d757461626c655f6e616d6573223a5b22636f6e74726f6c6c6572222c2264616f225d2c2273746f72616765223a5b7b226c6162656c223a2269734164646572222c22736c6f74223a2230222c226f6666736574223a302c2274797065223a22745f6d617070696e6728745f616464726573732c745f626f6f6c29227d2c7b226c6162656c223a2270656e64696e67436f6e74726f6c6c657241646d696e222c22736c6f74223a2231222c226f6666736574223a302c2274797065223a22745f61646472657373227d2c7b226c6162656c223a2272657469726564222c22736c6f74223a2231222c226f6666736574223a32302c2274797065223a22745f626f6f6c227d2c7b226c6162656c223a225f6c6f636b222c22736c6f74223a2232222c226f6666736574223a302c2274797065223a22745f75696e74323536227d5d2c227479706573223a7b22745f61646472657373223a7b22656e636f64696e67223a22696e706c616365222c226c6162656c223a2261646472657373222c226e756d6265724f664279746573223a223230227d2c22745f626f6f6c223a7b22656e636f64696e67223a22696e706c616365222c226c6162656c223a22626f6f6c222c226e756d6265724f664279746573223a2231227d2c22745f6d617070696e6728745f616464726573732c745f626f6f6c29223a7b22656e636f64696e67223a226d617070696e67222c226b6579223a22745f61646472657373222c226c6162656c223a226d617070696e672861646472657373203d3e20626f6f6c29222c226e756d6265724f664279746573223a223332222c2276616c7565223a22745f626f6f6c227d2c22745f75696e74323536223a7b22656e636f64696e67223a22696e706c616365222c226c6162656c223a2275696e74323536222c226e756d6265724f664279746573223a223332227d7d2c22636f6d70696c65645f65766964656e6365223a227265766965772f726f75746572706c616e2f70726f62652f6f75742f4761756765436f6e74726f6c6c657241646d696e457374696d6174652e736f6c2f4761756765436f6e74726f6c6c657241646d696e457374696d6174652e6a736f6e222c22636176656174223a2241424920636865636b656420616761696e737420746865207772697474656e2073706563696669636174696f6e3b206d6f64656c206973206e6f6e7368697070696e6720616e64206974732065786563757461626c6520627974657320617265204e4f5420616e20696d706c656d656e746174696f6e206d616e64617465227d"
    );

    // ------------------------------------------------------------------
    // low-level call helpers
    // ------------------------------------------------------------------

    function _call(address target, bytes memory data) internal returns (bool ok, bytes memory ret) {
        (ok, ret) = target.call(data);
    }

    /// @dev prank + low-level call: preserves exact revert bytes instead of
    /// bubbling them as the test's own revert.
    function _callFrom(address from, address target, bytes memory data) internal returns (bool ok, bytes memory ret) {
        vm.prank(from);
        (ok, ret) = target.call(data);
    }

    function _static(address target, bytes memory data) internal view returns (bool ok, bytes memory ret) {
        (ok, ret) = target.staticcall(data);
    }

    function _callValue(address target, bytes memory data, uint256 value) internal returns (bool ok, bytes memory ret) {
        (ok, ret) = target.call{value: value}(data);
    }

    /// @dev prank + value-bearing low-level call. An authorized control and
    /// its value probe come from the SAME otherwise-successful caller and
    /// differ only in msg.value, so no earlier authorization rejection can
    /// mask a missing nonpayable arm (CONF-03).
    function _callValueFrom(address from, address target, bytes memory data, uint256 value)
        internal
        returns (bool ok, bytes memory ret)
    {
        vm.prank(from);
        (ok, ret) = target.call{value: value}(data);
    }

    function _revertMatches(bytes memory actual, bytes memory expected, string memory label) internal pure {
        require(keccak256(actual) == keccak256(expected), label);
    }

    /// @dev True when `ret` is exactly `sel` followed by `args`.
    function _isError(bytes memory ret, bytes4 sel, bytes memory args) internal pure returns (bool) {
        if (ret.length != 4 + args.length) return false;
        bytes memory head = abi.encodePacked(sel);
        for (uint256 i = 0; i < 4; ++i) {
            if (head[i] != ret[i]) return false;
        }
        for (uint256 i = 0; i < args.length; ++i) {
            if (args[i] != ret[4 + i]) return false;
        }
        return true;
    }

    // ------------------------------------------------------------------
    // JSON field helpers (artifact side and manifest side share these)
    // ------------------------------------------------------------------

    function _u(uint256 v) internal pure returns (string memory) {
        if (v == 0) return "0";
        uint256 len;
        uint256 t = v;
        while (t > 0) {
            t /= 10;
            len++;
        }
        bytes memory b = new bytes(len);
        while (v > 0) {
            len--;
            b[len] = bytes1(uint8(48 + (v % 10)));
            v /= 10;
        }
        return string(b);
    }

    function _s(string memory json, string memory path) internal pure returns (string memory) {
        return rv.parseJsonString(json, path);
    }

    function _strEq(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }

    function _has(string memory json, string memory path) internal pure returns (bool) {
        return rv.keyExistsJson(json, path);
    }

    function _field(string memory base, uint256 index, string memory suffix) internal pure returns (string memory) {
        return string.concat(base, "[", _u(index), "].", suffix);
    }

    function _elem(string memory base, uint256 index) internal pure returns (string memory) {
        return string.concat(base, "[", _u(index), "]");
    }

    function _countArray(string memory json, string memory base) internal pure returns (uint256 n) {
        while (_has(json, _elem(base, n))) {
            n += 1;
        }
    }

    // ------------------------------------------------------------------
    // ABI comparison: artifact paths ($.abi[.]) vs manifest paths ($.abi[.])
    // run field-by-field over the two full documents.
    // ------------------------------------------------------------------

    function _cmpAt(
        string memory artJson,
        string memory expJson,
        string memory aPath,
        string memory ePath,
        string memory tag
    ) internal pure {
        require(_strEq(_s(artJson, aPath), _s(expJson, ePath)), tag);
    }

    function _cmpOptAt(
        string memory artJson,
        string memory expJson,
        string memory aPath,
        string memory ePath,
        string memory tag
    ) internal pure {
        bool aHas = _has(artJson, aPath);
        bool eHas = _has(expJson, ePath);
        require(aHas == eHas, tag);
        if (aHas) _cmpAt(artJson, expJson, aPath, ePath, tag);
    }

    function _cmpBoolAt(
        string memory artJson,
        string memory expJson,
        string memory aPath,
        string memory ePath,
        string memory tag
    ) internal pure {
        require(rv.parseJsonBool(artJson, aPath) == rv.parseJsonBool(expJson, ePath), tag);
    }

    /// @dev params under `$.abi[i].<bag>` on both documents.
    function _cmpBag(
        string memory artJson,
        string memory expJson,
        string memory aBag,
        string memory eBag,
        bool withIndexed,
        string memory tag
    ) internal pure {
        uint256 an = _countArray(artJson, aBag);
        uint256 bn = _countArray(expJson, eBag);
        require(an == bn, tag);
        for (uint256 i = 0; i < an; ++i) {
            _cmpAt(artJson, expJson, _field(aBag, i, "name"), _field(eBag, i, "name"), tag);
            _cmpAt(artJson, expJson, _field(aBag, i, "type"), _field(eBag, i, "type"), tag);
            _cmpAt(artJson, expJson, _field(aBag, i, "internalType"), _field(eBag, i, "internalType"), tag);
            if (withIndexed) {
                _cmpOptAt(artJson, expJson, _field(aBag, i, "indexed"), _field(eBag, i, "indexed"), tag);
                if (_has(artJson, _field(aBag, i, "indexed"))) {
                    _cmpBoolAt(artJson, expJson, _field(aBag, i, "indexed"), _field(eBag, i, "indexed"), tag);
                }
            }
        }
    }

    function _cmpItem(string memory artJson, string memory expJson, string memory tag, uint256 idx) internal pure {
        string memory aBase = _elem("$.abi", idx);
        string memory eBase = _elem("$.abi", idx);
        _cmpAt(artJson, expJson, string.concat(aBase, ".type"), string.concat(eBase, ".type"), tag);
        _cmpOptAt(artJson, expJson, string.concat(aBase, ".name"), string.concat(eBase, ".name"), tag);
        _cmpOptAt(
            artJson, expJson, string.concat(aBase, ".stateMutability"), string.concat(eBase, ".stateMutability"), tag
        );
        bool aAnon = _has(artJson, string.concat(aBase, ".anonymous"));
        bool eAnon = _has(expJson, string.concat(eBase, ".anonymous"));
        require(aAnon == eAnon, tag);
        if (aAnon) {
            _cmpBoolAt(artJson, expJson, string.concat(aBase, ".anonymous"), string.concat(eBase, ".anonymous"), tag);
        }
        _cmpBag(artJson, expJson, string.concat(aBase, ".inputs"), string.concat(eBase, ".inputs"), true, tag);
        bool aOut = _has(artJson, string.concat(aBase, ".outputs"));
        bool eOut = _has(expJson, string.concat(eBase, ".outputs"));
        require(aOut == eOut, tag);
        if (aOut) {
            _cmpBag(artJson, expJson, string.concat(aBase, ".outputs"), string.concat(eBase, ".outputs"), false, tag);
        }
    }

    /// @dev Full recursive ABI equality over the two documents: identical
    /// item counts, then every entry compared field-by-field, positionally.
    function _assertAbiMatchesArtifact(string memory artJson) internal pure {
        uint256 nArt = _countArray(artJson, "$.abi");
        uint256 nExp = _countArray(MANIFEST_JSON, "$.abi");
        require(nArt == nExp, "ABI_EXACT_SURFACE item count");
        require(nArt == 32, "ABI_EXACT_SURFACE expected 32 items");
        for (uint256 i = 0; i < nArt; ++i) {
            _cmpItem(artJson, MANIFEST_JSON, "ABI_EXACT_SURFACE item", i);
        }
        for (uint256 j = 0; j < nArt; ++j) {
            string memory ty = _s(artJson, _field("$.abi", j, "type"));
            require(!_strEq(ty, "fallback") && !_strEq(ty, "receive"), "ABI_EXACT_SURFACE no fallback/receive");
        }
    }

    function _assertMethodIdsMatchArtifact(string memory artJson) internal pure {
        string[] memory artKeys = rv.parseJsonKeys(artJson, "$.methodIdentifiers");
        string[] memory expKeys = rv.parseJsonKeys(MANIFEST_JSON, "$.methodIdentifiers");
        require(artKeys.length == 12, "ABI_EXACT_SURFACE method count");
        require(artKeys.length == expKeys.length, "ABI_EXACT_SURFACE method count equal");
        for (uint256 i = 0; i < artKeys.length; ++i) {
            bool found;
            uint256 j;
            while (!found && j < expKeys.length) {
                if (_strEq(artKeys[i], expKeys[j])) found = true;
                j++;
            }
            require(found, "ABI_EXACT_SURFACE method signature");
            _cmpAt(
                artJson,
                MANIFEST_JSON,
                string.concat('$.methodIdentifiers["', artKeys[i], '"]'),
                string.concat('$.methodIdentifiers["', artKeys[i], '"]'),
                "ABI_EXACT_SURFACE selector value"
            );
        }
    }

    function _assertStorageMatchesManifest(string memory artJson) internal pure {
        uint256 nArt = _countArray(artJson, "$.storageLayout.storage");
        uint256 nExp = _countArray(MANIFEST_JSON, "$.storage");
        require(nArt == nExp, "ABI_EXACT_SURFACE storage count");
        require(nArt == 4, "ABI_EXACT_SURFACE four storage entries");
        for (uint256 i = 0; i < nArt; ++i) {
            _cmpAt(
                artJson,
                MANIFEST_JSON,
                _field("$.storageLayout.storage", i, "label"),
                _field("$.storage", i, "label"),
                "ABI_EXACT_SURFACE storage label"
            );
            _cmpAt(
                artJson,
                MANIFEST_JSON,
                _field("$.storageLayout.storage", i, "slot"),
                _field("$.storage", i, "slot"),
                "ABI_EXACT_SURFACE storage slot"
            );
            _cmpAt(
                artJson,
                MANIFEST_JSON,
                _field("$.storageLayout.storage", i, "offset"),
                _field("$.storage", i, "offset"),
                "ABI_EXACT_SURFACE storage offset"
            );
            _cmpAt(
                artJson,
                MANIFEST_JSON,
                _field("$.storageLayout.storage", i, "type"),
                _field("$.storage", i, "type"),
                "ABI_EXACT_SURFACE storage type"
            );
        }
        string[] memory expTypes = rv.parseJsonKeys(MANIFEST_JSON, "$.types");
        require(expTypes.length == 4, "ABI_EXACT_SURFACE four manifest types");
        for (uint256 i = 0; i < expTypes.length; ++i) {
            string memory tkey = expTypes[i];
            string memory aT = string.concat('$.storageLayout.types["', tkey, '"].');
            string memory eT = string.concat('$.types["', tkey, '"].');
            _cmpAt(
                artJson,
                MANIFEST_JSON,
                string.concat(aT, "encoding"),
                string.concat(eT, "encoding"),
                "ABI_EXACT_SURFACE type encoding"
            );
            _cmpAt(
                artJson,
                MANIFEST_JSON,
                string.concat(aT, "numberOfBytes"),
                string.concat(eT, "numberOfBytes"),
                "ABI_EXACT_SURFACE type bytes"
            );
            _cmpOptAt(
                artJson,
                MANIFEST_JSON,
                string.concat(aT, "key"),
                string.concat(eT, "key"),
                "ABI_EXACT_SURFACE mapping key type"
            );
            _cmpOptAt(
                artJson,
                MANIFEST_JSON,
                string.concat(aT, "value"),
                string.concat(eT, "value"),
                "ABI_EXACT_SURFACE mapping value type"
            );
        }
        // immutables must be embedded, never slot-backed storage (solc
        // omits the immutable map entirely when nothing is slot-backed)
        if (_has(artJson, "$.storageLayout.immutable")) {
            string[] memory immKeys = rv.parseJsonKeys(artJson, "$.storageLayout.immutable");
            require(immKeys.length == 0, "ABI_EXACT_SURFACE embedded immutables only");
        }
    }

    function _artifactJson() internal view returns (string memory) {
        return rv.readFile("out/GaugeControllerAdmin.sol/GaugeControllerAdmin.json");
    }

    // ------------------------------------------------------------------
    // role fixtures
    // ------------------------------------------------------------------

    struct Fixture {
        RouterControllerMock c;
        GaugeControllerAdmin r;
        RouterDaoShim dao;
        RouterAdderShim adder;
        address deployer;
    }

    /// @dev Fresh C + R(C,D), unseated. D is the code-bearing DAO shim so
    /// controller-hook callbacks can re-enter R as an AUTHORIZED caller; the
    /// deployer is the test contract, distinct from D.
    function _freshFixture() internal returns (Fixture memory f) {
        RouterDaoShim dao = new RouterDaoShim();
        RouterControllerMock c = new RouterControllerMock(address(dao), 2);
        GaugeControllerAdmin r = new GaugeControllerAdmin(address(c), address(dao));
        dao.setRouter(r);
        RouterAdderShim adder = new RouterAdderShim();
        adder.setRouter(r);
        f = Fixture({c: c, r: r, dao: dao, adder: adder, deployer: address(this)});
    }

    /// @dev Fresh fixture with R seated as C admin via the raw D→C two-step
    /// (pre-router installation): C.admin==R, C.future_admin==R (stale),
    /// R.pendingControllerAdmin==0.
    function _seatedFixture() internal returns (Fixture memory f) {
        f = _freshFixture();
        _seatRaw(f);
    }

    function _seatRaw(Fixture memory f) internal {
        vm.startPrank(address(f.dao));
        f.c.commit_transfer_ownership(address(f.r));
        f.c.apply_transfer_ownership();
        vm.stopPrank();
        require(f.c.admin() == address(f.r), "seat admin");
    }

    function _grant(Fixture memory f, address who, bool enabled) internal {
        vm.prank(address(f.dao));
        f.r.grant(who, enabled);
    }

    /// @dev D-directed router commit+apply (handback/ownership completion).
    function _handback(Fixture memory f, address successor) internal {
        vm.startPrank(address(f.dao));
        f.r.commit_transfer_ownership(successor);
        f.r.apply_transfer_ownership();
        vm.stopPrank();
    }
}
